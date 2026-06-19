import Combine
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
        cropState.reset(for: resolution.aspectRatio)
        screen = .crop
    }

    func cancelCrop() {
        screen = .main
    }

    func confirmCrop(imageDisplayRect: CGRect, imagePixelSize: CGSize) {
        confirmedCropRect = cropState.cropRectInImageCoordinates(
            imageDisplayRect: imageDisplayRect,
            imagePixelSize: imagePixelSize
        )
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
            if let data = try await selectedPhotoItem.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                sourceImage = image.normalizedOrientation()
                cropState.reset(for: resolution.aspectRatio)
            }
        } catch {
            errorMessage = "Foto laden mislukt."
        }
    }

    // MARK: - Processing

    func startProcessing(direction: ScrollDirection) {
        guard let sourceImage else { return }

        isProcessing = true
        frames = []
        gifData = nil
        stopAnimation()

        let cropRect = confirmedCropRect
        let resolution = resolution
        let processor = ImageProcessor()

        Task {
            let generated = await Task.detached(priority: .userInitiated) {
                processor.generateScrollAnimation(
                    from: sourceImage,
                    cropRect: cropRect,
                    resolution: resolution,
                    direction: direction
                )
            }.value

            frames = generated.compactMap { UIImage(cgImage: $0) }
            gifData = GIFExporter.makeGIF(from: generated)
            isProcessing = false

            if frames.isEmpty {
                errorMessage = "Animatie kon niet worden gegenereerd."
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
        guard !frames.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        let cgFrames = frames.compactMap(\.cgImage)
        guard let data = gifData ?? GIFExporter.makeGIF(from: cgFrames) else {
            errorMessage = "GIF export mislukt."
            return
        }

        do {
            try await PhotoLibrarySaver.saveGIF(data)
            saveSuccessMessage = "GIF opgeslagen in Fotobibliotheek."
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
        cropState.aspectRatio = resolution.aspectRatio
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
        let overlay = overlayRect(in: imageDisplayRect.size)
        let relative = CGRect(
            x: (overlay.minX - imageDisplayRect.minX) / imageDisplayRect.width,
            y: (overlay.minY - imageDisplayRect.minY) / imageDisplayRect.height,
            width: overlay.width / imageDisplayRect.width,
            height: overlay.height / imageDisplayRect.height
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
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
