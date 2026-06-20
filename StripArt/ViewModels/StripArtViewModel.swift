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
    @Published var scrollDirection: ScrollDirection?

    // MARK: - Flow state

    @Published private(set) var screen: AppScreen = .main
    @Published private(set) var frames: [UIImage] = []
    @Published private(set) var gifData: Data?
    @Published private(set) var isProcessing = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published var saveSuccessMessage: String?

    // MARK: - Animation

    @Published private(set) var currentFrameIndex = 0
    private var animationTask: Task<Void, Never>?
    private var cgFrames: [CGImage] = []

    private var confirmedCropRect: CGRect = .zero

    var resolutionIsValid: Bool {
        resolution.isValid
    }

    var canProceedFromMain: Bool {
        resolutionIsValid && sourceImage != nil
    }

    // MARK: - Navigation

    func goToCrop() {
        guard canProceedFromMain else { return }
        syncResolutionFromText()
        var state = cropState
        state.reset(for: resolution.aspectRatio)
        cropState = state
        screen = .crop
    }

    func cancelCrop() {
        screen = .main
    }

    func confirmCrop(imageDisplayRect: CGRect, imagePixelSize: CGSize) {
        let cropRect = cropState.cropRectInImageCoordinates(
            imageDisplayRect: imageDisplayRect,
            imagePixelSize: imagePixelSize
        )
        guard cropRect.width > 1, cropRect.height > 1 else {
            errorMessage = "Invalid selection. Please try again."
            return
        }
        confirmedCropRect = cropRect
        screen = .direction
    }

    func cancelDirection() {
        screen = .crop
    }

    func selectDirection(_ direction: ScrollDirection) {
        scrollDirection = direction
        screen = .preview
        startProcessing(direction: direction)
    }

    func cancelPreview() {
        stopAnimation()
        frames = []
        cgFrames = []
        gifData = nil
        scrollDirection = nil
        screen = .main
        selectedPhotoItem = nil
        sourceImage = nil
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

    func startProcessing(direction: ScrollDirection) {
        guard let sourceImage else { return }

        isProcessing = true
        frames = []
        cgFrames = []
        gifData = nil
        stopAnimation()

        let cropRect = confirmedCropRect
        let resolution = resolution
        let processor = ImageProcessor()

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                let generated = processor.generateScrollAnimation(
                    from: sourceImage,
                    cropRect: cropRect,
                    resolution: resolution,
                    direction: direction
                )
                let uiFrames = generated.map { UIImage(cgImage: $0) }
                return (generated, uiFrames)
            }.value

            cgFrames = result.0
            frames = result.1
            isProcessing = false

            if frames.isEmpty {
                errorMessage = "Could not generate animation."
            } else {
                startAnimation()
            }
        }
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
            saveSuccessMessage = "GIF saved to Photo Library."
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
