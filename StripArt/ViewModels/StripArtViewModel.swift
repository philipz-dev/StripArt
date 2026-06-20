import Combine
import ImageIO
import PhotosUI
import SwiftUI
import UIKit

@MainActor
final class StripArtViewModel: ObservableObject {

    // MARK: - Input state

    @Published var resolution = LEDResolution.default
    @Published var heightText = "16"
    @Published var widthText = "96"
    @Published var selectedPhotoItem: PhotosPickerItem?
    @Published var sourceImage: UIImage?
    @Published var cropState = CropOverlayState()
    @Published var scrollDirection: ScrollDirection? = .down
    @Published var ditherAlgorithm: DitherAlgorithm = .floydSteinberg

    /// Two-step crop: first pick start size & position, then the end position.
    @Published private(set) var cropPhase: CropPhase = .start

    // MARK: - Flow state

    @Published private(set) var screen: AppScreen = .main
    @Published private(set) var frames: [UIImage] = []
    @Published private(set) var gifData: Data?
    @Published private(set) var isProcessing = false
    @Published private(set) var isReprocessingDither = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published var saveSuccessMessage: String?

    // MARK: - Frame rate

    /// Number of frames the user wants in the bounce. Defaults to the full
    /// 1-pixel-per-step count and can only be decreased, never increased.
    @Published var frameCount: Int = 0
    @Published private(set) var maxFrameCount: Int = 0
    @Published private(set) var isPreparingFrames = false

    /// Smallest meaningful animation length.
    let minFrameCount = 2

    // MARK: - Animation

    @Published private(set) var currentFrameIndex = 0
    private var animationTask: Task<Void, Never>?
    private var cgFrames: [CGImage] = []
    /// Full 1-pixel-per-step bounce; user selections subsample from this.
    private var fullCgFrames: [CGImage] = []
    /// Undithered scroll strip kept for live algorithm switching in preview.
    private var scrollAnimationSource: ScrollAnimationSource?

    private var confirmedCropRect: CGRect = .zero
    /// End viewport (same size as start) in image pixel coordinates.
    private var endCropRect: CGRect = .zero
    /// Normalized overlay center captured when the start phase is confirmed.
    private var phaseStartCenter: CGPoint = CGPoint(x: 0.5, y: 0.5)

    var resolutionIsValid: Bool {
        resolution.isValid
    }

    var canProceedFromMain: Bool {
        resolutionIsValid && sourceImage != nil
    }

    // MARK: - Navigation

    func clearSelectedPhoto() {
        selectedPhotoItem = nil
        sourceImage = nil
    }

    func goToCrop() {
        guard canProceedFromMain else { return }
        syncResolutionFromText()
        var state = cropState
        state.reset(for: resolution.aspectRatio)
        cropState = state
        cropPhase = .start
        scrollDirection = .down
        screen = .crop
    }

    /// X button on the crop screen.
    func cancelCrop() {
        if cropPhase == .end {
            // Step back to choosing the start size & position.
            cropPhase = .start
        } else {
            screen = .main
        }
    }

    func selectScrollDirection(_ direction: ScrollDirection) {
        scrollDirection = direction
        // When changing direction during the end phase, restart from the start
        // position so movement is valid along the new axis.
        if cropPhase == .end {
            var state = cropState
            state.center = phaseStartCenter
            cropState = state
        }
    }

    /// Checkmark in the start phase: lock the size, switch to choosing the end.
    func confirmStartPhase(imageDisplayRect: CGRect, imagePixelSize: CGSize) {
        let cropRect = cropState.cropRectInImageCoordinates(
            imageDisplayRect: imageDisplayRect,
            imagePixelSize: imagePixelSize
        )
        guard cropRect.width > 1, cropRect.height > 1 else {
            errorMessage = "Invalid selection. Please try again."
            return
        }
        confirmedCropRect = cropRect
        phaseStartCenter = cropState.center
        cropPhase = .end
    }

    /// Checkmark in the end phase: capture the end position and continue.
    func confirmEndPhase(imageDisplayRect: CGRect, imagePixelSize: CGSize) {
        guard let direction = scrollDirection else { return }
        endCropRect = cropState.cropRectInImageCoordinates(
            imageDisplayRect: imageDisplayRect,
            imagePixelSize: imagePixelSize
        )
        screen = .frameRate
        prepareAnimation(direction: direction)
    }

    /// Restricts the end-phase overlay to move only along (and in) the arrow's direction.
    func constrainedEndCenter(_ proposed: CGPoint) -> CGPoint {
        guard let direction = scrollDirection else { return proposed }
        switch direction.scrollAxis {
        case .vertical:
            let y = direction == .down
                ? max(phaseStartCenter.y, proposed.y)
                : min(phaseStartCenter.y, proposed.y)
            return CGPoint(x: phaseStartCenter.x, y: y)
        case .horizontal:
            let x = direction == .right
                ? max(phaseStartCenter.x, proposed.x)
                : min(phaseStartCenter.x, proposed.x)
            return CGPoint(x: x, y: phaseStartCenter.y)
        }
    }

    func cancelFrameRate() {
        stopAnimation()
        cropPhase = .end
        screen = .crop
    }

    func confirmFrameRate() {
        guard !fullCgFrames.isEmpty else { return }

        let selected = min(max(minFrameCount, frameCount), maxFrameCount)
        let subsampled = Self.subsample(fullCgFrames, to: selected)

        cgFrames = subsampled
        frames = subsampled.map { UIImage(cgImage: $0) }
        gifData = nil
        screen = .preview
        startAnimation()
    }

    func cancelPreview() {
        stopAnimation()
        frames = []
        cgFrames = []
        gifData = nil
        screen = .frameRate
    }

    func returnToMain() {
        stopAnimation()
        frames = []
        cgFrames = []
        fullCgFrames = []
        scrollAnimationSource = nil
        gifData = nil
        frameCount = 0
        maxFrameCount = 0
        scrollDirection = .down
        ditherAlgorithm = .floydSteinberg
        cropPhase = .start
        endCropRect = .zero
        selectedPhotoItem = nil
        sourceImage = nil
        screen = .main
    }

    // MARK: - Photo loading

    func loadSelectedPhoto() async {
        guard let selectedPhotoItem else { return }

        do {
            if let data = try await selectedPhotoItem.loadTransferable(type: Data.self) {
                let image = UIImage.downsampled(from: data, maxPixelSize: 2048)
                    ?? UIImage(data: data)
                if let image {
                    sourceImage = image.normalizedOrientation()
                    var state = cropState
                    state.reset(for: resolution.aspectRatio)
                    cropState = state
                }
            }
        } catch {
            errorMessage = "Failed to load photo."
        }
    }

    // MARK: - Processing

    /// Generates the full 1-pixel-per-step bounce so the frame-rate screen knows
    /// the maximum frame count. The user can then subsample down from this.
    private func prepareAnimation(direction: ScrollDirection) {
        guard let sourceImage else { return }

        isPreparingFrames = true
        frames = []
        cgFrames = []
        fullCgFrames = []
        scrollAnimationSource = nil
        gifData = nil
        maxFrameCount = 0
        stopAnimation()

        let cropRect = confirmedCropRect
        let endRect = endCropRect
        let resolution = resolution
        let algorithm = ditherAlgorithm
        let processor = ImageProcessor()

        Task {
            let source = await Task.detached(priority: .userInitiated) {
                processor.prepareScrollAnimationSource(
                    from: sourceImage,
                    cropRect: cropRect,
                    endCropRect: endRect,
                    resolution: resolution,
                    direction: direction
                )
            }.value

            guard let source else {
                isPreparingFrames = false
                errorMessage = "Could not generate animation."
                cropPhase = .end
                screen = .crop
                return
            }

            scrollAnimationSource = source

            let generated = await Task.detached(priority: .userInitiated) {
                processor.renderScrollAnimation(from: source, algorithm: algorithm)
            }.value

            fullCgFrames = generated
            maxFrameCount = generated.count
            frameCount = generated.count
            isPreparingFrames = false

            if generated.isEmpty {
                errorMessage = "Could not generate animation."
                cropPhase = .end
                screen = .crop
            }
        }
    }

    func selectDitherAlgorithm(_ algorithm: DitherAlgorithm) {
        guard algorithm != ditherAlgorithm,
              scrollAnimationSource != nil,
              screen == .preview else {
            return
        }

        ditherAlgorithm = algorithm
        reapplyDitherAlgorithm()
    }

    private func reapplyDitherAlgorithm() {
        guard let source = scrollAnimationSource else { return }

        stopAnimation()
        isReprocessingDither = true
        gifData = nil

        let algorithm = ditherAlgorithm
        let selectedFrameCount = min(max(minFrameCount, frameCount), maxFrameCount)
        let processor = ImageProcessor()

        Task {
            let rendered = await Task.detached(priority: .userInitiated) {
                processor.renderScrollAnimation(from: source, algorithm: algorithm)
            }.value

            fullCgFrames = rendered
            maxFrameCount = rendered.count

            let subsampled = Self.subsample(rendered, to: selectedFrameCount)
            cgFrames = subsampled
            frames = subsampled.map { UIImage(cgImage: $0) }
            isReprocessingDither = false
            startAnimation()
        }
    }

    /// Evenly picks `count` frames from `frames`, preserving the first and last.
    private static func subsample(_ frames: [CGImage], to count: Int) -> [CGImage] {
        guard count > 0 else { return [] }
        guard frames.count > count else { return frames }
        guard count > 1 else { return [frames[0]] }

        let last = frames.count - 1
        var result = [CGImage]()
        result.reserveCapacity(count)
        for i in 0..<count {
            let position = Double(i) * Double(last) / Double(count - 1)
            result.append(frames[Int(position.rounded())])
        }
        return result
    }

    // MARK: - Animation playback

    func startAnimation() {
        stopAnimation()
        guard !frames.isEmpty else { return }

        animationTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled, !frames.isEmpty else { break }
                currentFrameIndex = (currentFrameIndex + 1) % frames.count
            }
        }
    }

    func stopAnimation() {
        animationTask?.cancel()
        animationTask = nil
        currentFrameIndex = 0
    }

    // MARK: - Save

    func saveGIF() async {
        guard !cgFrames.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        let framesToExport = cgFrames
        let data = await Task.detached(priority: .userInitiated) {
            GIFExporter.makeGIF(from: framesToExport)
        }.value

        guard let data else {
            errorMessage = "GIF export failed."
            return
        }

        gifData = data

        do {
            try await PhotoLibrarySaver.saveGIF(data)
            returnToMain()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Resolution sync

    func syncResolutionFromText() {
        let height = Int(heightText.filter(\.isNumber)) ?? LEDResolution.default.height
        let width = Int(widthText.filter(\.isNumber)) ?? LEDResolution.default.width
        resolution = LEDResolution(
            height: max(1, min(256, height)),
            width: max(1, min(512, width))
        )
        heightText = String(resolution.height)
        widthText = String(resolution.width)
        var state = cropState
        state.aspectRatio = resolution.aspectRatio
        cropState = state
    }

    func mutateCropState(in containerSize: CGSize, _ mutate: (inout CropOverlayState) -> Void) {
        var state = cropState
        mutate(&state)
        state.clamp(in: containerSize)
        cropState = state
    }

    func clampCropState(in containerSize: CGSize) {
        var state = cropState
        state.clamp(in: containerSize)
        cropState = state
    }
}

// MARK: - Crop overlay state

struct CropOverlayState {
    var center: CGPoint = CGPoint(x: 0.5, y: 0.5)
    var scale: CGFloat = 0.8
    var aspectRatio: CGFloat = LEDResolution.default.aspectRatio

    mutating func reset(for aspectRatio: CGFloat) {
        self.aspectRatio = aspectRatio
        center = CGPoint(x: 0.5, y: 0.5)
        scale = 0.8
    }

    func overlayRect(in containerSize: CGSize) -> CGRect {
        let containerAspect = containerSize.width / max(containerSize.height, 1)
        var overlayWidth: CGFloat
        var overlayHeight: CGFloat

        if aspectRatio > containerAspect {
            overlayWidth = containerSize.width * scale
            overlayHeight = overlayWidth / aspectRatio
        } else {
            overlayHeight = containerSize.height * scale
            overlayWidth = overlayHeight * aspectRatio
        }

        let originX = center.x * containerSize.width - overlayWidth / 2
        let originY = center.y * containerSize.height - overlayHeight / 2

        return CGRect(x: originX, y: originY, width: overlayWidth, height: overlayHeight)
    }

    mutating func clamp(in containerSize: CGSize) {
        var rect = overlayRect(in: containerSize)
        let maxWidth = containerSize.width
        let maxHeight = containerSize.height

        if rect.width > maxWidth {
            let s = maxWidth / rect.width
            scale *= s
            rect = overlayRect(in: containerSize)
        }
        if rect.height > maxHeight {
            let s = maxHeight / rect.height
            scale *= s
            rect = overlayRect(in: containerSize)
        }

        let clampedX = min(max(rect.midX, rect.width / 2), containerSize.width - rect.width / 2)
        let clampedY = min(max(rect.midY, rect.height / 2), containerSize.height - rect.height / 2)
        center = CGPoint(
            x: clampedX / containerSize.width,
            y: clampedY / containerSize.height
        )
    }

    func cropRectInImageCoordinates(
        imageDisplayRect: CGRect,
        imagePixelSize: CGSize
    ) -> CGRect {
        let displaySize = imageDisplayRect.size
        guard displaySize.width > 0, displaySize.height > 0 else { return .zero }

        // Overlay is expressed in local image-view coordinates (origin 0,0).
        let overlay = overlayRect(in: displaySize)
        let relative = CGRect(
            x: overlay.minX / displaySize.width,
            y: overlay.minY / displaySize.height,
            width: overlay.width / displaySize.width,
            height: overlay.height / displaySize.height
        )

        let pixelRect = CGRect(
            x: relative.origin.x * imagePixelSize.width,
            y: relative.origin.y * imagePixelSize.height,
            width: relative.width * imagePixelSize.width,
            height: relative.height * imagePixelSize.height
        )

        return pixelRect.intersection(
            CGRect(origin: .zero, size: imagePixelSize)
        )
    }
}

// MARK: - UIImage helpers

private extension UIImage {
    static func downsampled(from data: Data, maxPixelSize: Int) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
