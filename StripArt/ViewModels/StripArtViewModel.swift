import Combine
import ImageIO
import PhotosUI
import SwiftUI
import UIKit

@MainActor
final class StripArtViewModel: ObservableObject {

    // MARK: - Input state

    @Published var resolution = LEDResolution.default
    @Published var heightText: String
    @Published var widthText: String
    @Published var selectedPhotoItem: PhotosPickerItem?
    @Published var sourceImage: UIImage?
    @Published var cropState = CropOverlayState()
    @Published var scrollDirection: ScrollDirection? = .down
    @Published var ditherAlgorithm: DitherAlgorithm = .ordered

    /// Contrast applied before dithering. -1 = flat, 0 = unchanged, 1 = strong.
    @Published var contrast: Double = 0
    /// Single, non-animated frame shown on the dithering and contrast screens.
    @Published private(set) var stillPreview: UIImage?
    @Published private(set) var isRenderingStill = false

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
    @Published private(set) var showSaveConfirmation = false
    @Published var showPaywall = false

    // MARK: - Free export limit

    /// Number of animations that can be saved before the unlock is required.
    let freeExportLimit = 5
    @Published private(set) var freeExportsUsed = UserDefaults.standard.integer(forKey: "freeExportsUsed")

    var remainingFreeExports: Int {
        max(0, freeExportLimit - freeExportsUsed)
    }

    var hasFreeExportsLeft: Bool {
        freeExportsUsed < freeExportLimit
    }

    // MARK: - Frame rate

    /// Number of frames the user wants in the bounce. Defaults to the full
    /// 1-pixel-per-step count and can only be decreased, never increased.
    @Published var frameCount: Int = 0
    @Published private(set) var maxFrameCount: Int = 0
    @Published private(set) var isPreparingFrames = false

    /// Smallest meaningful animation length.
    let minFrameCount = 2

    init() {
        let saved = LEDResolution.loadSaved() ?? LEDResolution.default
        resolution = saved
        heightText = String(saved.height)
        widthText = String(saved.width)
        cropState.aspectRatio = saved.aspectRatio
    }

    // MARK: - Animation

    @Published private(set) var currentFrameIndex = 0
    private var animationTask: Task<Void, Never>?
    private var stillRenderTask: Task<Void, Never>?
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
        normalizeResolutionText()
        guard canProceedFromMain else { return }
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

    /// Checkmark on the frame-rate screen: move on to the appearance screen where
    /// dithering and contrast are tuned on the whole static strip (no motion).
    func confirmFrameRate() {
        guard !fullCgFrames.isEmpty else { return }
        stopAnimation()
        screen = .appearance
        renderStillPreview()
    }

    /// X on the appearance screen: step back to the frame-rate slider.
    func cancelAppearance() {
        screen = .frameRate
    }

    /// Checkmark on the appearance screen: render the final animation and preview it.
    func confirmAppearance() {
        guard let source = scrollAnimationSource else { return }

        stillRenderTask?.cancel()
        stopAnimation()
        isReprocessingDither = true
        gifData = nil
        screen = .preview

        let algorithm = ditherAlgorithm
        let contrastValue = contrast
        let selected = min(max(minFrameCount, frameCount), maxFrameCount)
        let processor = ImageProcessor()

        Task {
            let rendered = await Task.detached(priority: .userInitiated) {
                processor.renderScrollAnimation(
                    from: source,
                    algorithm: algorithm,
                    contrast: contrastValue
                )
            }.value

            fullCgFrames = rendered
            maxFrameCount = rendered.count

            let subsampled = Self.subsample(rendered, to: selected)
            cgFrames = subsampled
            frames = subsampled.map { UIImage(cgImage: $0) }
            isReprocessingDither = false
            startAnimation()
        }
    }

    /// Re-renders the still preview using the current algorithm and contrast.
    func renderStillPreview() {
        guard let source = scrollAnimationSource else { return }

        stillRenderTask?.cancel()
        isRenderingStill = true

        let algorithm = ditherAlgorithm
        let contrastValue = contrast
        let processor = ImageProcessor()

        stillRenderTask = Task {
            let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let cgImage = processor.renderStrip(
                    from: source,
                    algorithm: algorithm,
                    contrast: contrastValue
                ) else { return nil }
                return UIImage(cgImage: cgImage)
            }.value

            if Task.isCancelled { return }
            stillPreview = image
            isRenderingStill = false
        }
    }

    func cancelPreview() {
        stopAnimation()
        frames = []
        cgFrames = []
        gifData = nil
        screen = .appearance
        renderStillPreview()
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
        ditherAlgorithm = .ordered
        contrast = 0
        stillPreview = nil
        stillRenderTask?.cancel()
        cropPhase = .start
        endCropRect = .zero
        showSaveConfirmation = false
        selectedPhotoItem = nil
        sourceImage = nil
        screen = .main
    }

    // MARK: - Photo loading

    func setCapturedImage(_ image: UIImage) {
        sourceImage = image.normalizedOrientation()
        selectedPhotoItem = nil
        var state = cropState
        state.reset(for: resolution.aspectRatio)
        cropState = state
    }

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
              scrollAnimationSource != nil else {
            return
        }

        ditherAlgorithm = algorithm

        switch screen {
        case .appearance:
            renderStillPreview()
        case .preview:
            reapplyDitherAlgorithm()
        default:
            break
        }
    }

    private func reapplyDitherAlgorithm() {
        guard let source = scrollAnimationSource else { return }

        stopAnimation()
        isReprocessingDither = true
        gifData = nil

        let algorithm = ditherAlgorithm
        let contrastValue = contrast
        let selectedFrameCount = min(max(minFrameCount, frameCount), maxFrameCount)
        let processor = ImageProcessor()

        Task {
            let rendered = await Task.detached(priority: .userInitiated) {
                processor.renderScrollAnimation(from: source, algorithm: algorithm, contrast: contrastValue)
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

    /// Saves the animation. When the user has not unlocked unlimited exports,
    /// this consumes one of the free exports; the caller is responsible for
    /// presenting the paywall first when no free exports remain.
    func saveGIF(unlocked: Bool) async {
        guard !cgFrames.isEmpty else { return }
        guard unlocked || hasFreeExportsLeft else {
            showPaywall = true
            return
        }

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
            if !unlocked {
                consumeFreeExport()
            }
            stopAnimation()
            showSaveConfirmation = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func consumeFreeExport() {
        freeExportsUsed += 1
        UserDefaults.standard.set(freeExportsUsed, forKey: "freeExportsUsed")
    }

    func confirmSaveSuccess() {
        showSaveConfirmation = false
        returnToMain()
    }

    // MARK: - Resolution sync

    /// Updates the resolution from the live text fields without forcing the text
    /// back, so a field can be cleared and retyped. Empty input maps to 0 (invalid).
    func syncResolutionFromText() {
        let height = Int(heightText.filter(\.isNumber)) ?? 0
        let width = Int(widthText.filter(\.isNumber)) ?? 0
        resolution = LEDResolution(
            height: min(256, height),
            width: min(512, width)
        )
        if resolution.isValid {
            var state = cropState
            state.aspectRatio = resolution.aspectRatio
            cropState = state
        }
    }

    /// Normalizes the text fields to the clamped values once editing finishes.
    func normalizeResolutionText() {
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
        resolution.save()
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
