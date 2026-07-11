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
    @Published var playbackMode: PlaybackMode = .bounce

    /// Contrast applied before dithering. -1 = flat, 0 = unchanged, 1 = strong.
    @Published var contrast: Double = 0
    /// Brightness applied before dithering. -1 = darker, 0 = unchanged, 1 = brighter.
    @Published var brightness: Double = 0
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

    #if DEBUG
    func resetTestingState() {
        freeExportsUsed = 0
        showPaywall = false
        screen = .main
        returnToMain()
    }
    #endif

    // MARK: - Frame rate

    /// Number of frames the user wants in the bounce. Defaults to the sweet
    /// spot (~100) when available; can only be decreased, never increased.
    @Published var frameCount: Int = 0
    @Published private(set) var maxFrameCount: Int = 0
    @Published private(set) var isPreparingFrames = false

    /// Smallest meaningful animation length.
    let minFrameCount = 2

    /// Default slider position on the frame-rate screen.
    private let sweetSpotFrameCount = 100

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
    /// Photo transform captured when the start phase is confirmed, so the end
    /// phase can start from the exact same view (no jump) and only pan from there.
    private(set) var phaseStartOffset: CGSize = .zero
    private(set) var phaseStartScale: CGFloat = 1.0
    /// Photo transform captured when the end phase is confirmed, so returning
    /// from later screens can restore the chosen end framing.
    private var phaseEndOffset: CGSize = .zero
    private var phaseEndScale: CGFloat = 1.0
    private var pendingEndTransformRestore = false

    var resolutionIsValid: Bool {
        resolution.isValid
    }

    static let photoResolutionMin = LEDResolution.minDimension
    static let photoResolutionMax = LEDResolution.maxDimension

    var resolutionIsValidForPhotoImport: Bool {
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
        contrast = 0
        brightness = 0
        var state = cropState
        state.reset(for: resolution.aspectRatio)
        cropState = state
        endCropRect = .zero
        phaseEndOffset = .zero
        phaseEndScale = 1.0
        pendingEndTransformRestore = false
        cropPhase = .start
        scrollDirection = .down
        screen = .crop
    }

    /// X button on the crop screen.
    func cancelCrop(geometry: CropGeometry? = nil) {
        if cropPhase == .end {
            cropPhase = .start
            endCropRect = .zero
            phaseEndOffset = .zero
            phaseEndScale = 1.0
            pendingEndTransformRestore = false
            restoreStartPhaseTransform(geometry: geometry)
        } else {
            // Going back from the start phase returns to the setup screen, so
            // the selected photo is cleared (there is no photo review step).
            selectedPhotoItem = nil
            sourceImage = nil
            screen = .main
        }
    }

    /// Puts the photo back exactly where it was when the start phase was confirmed.
    private func restoreStartPhaseTransform(geometry: CropGeometry?) {
        let scale = phaseStartScale
        let offset: CGSize
        if let geometry, confirmedCropRect != .zero {
            offset = geometry.offset(for: confirmedCropRect, scale: scale)
        } else {
            offset = phaseStartOffset
        }

        cropState = CropOverlayState(
            aspectRatio: cropState.aspectRatio,
            scale: scale,
            offset: offset
        )

        if let geometry {
            normalizeCropTransform(geometry: geometry)
        }
    }

    /// Puts the photo back exactly where it was when the end phase was confirmed.
    private func restoreEndPhaseTransform(geometry: CropGeometry?) {
        let scale = phaseEndScale
        let offset: CGSize
        if let geometry, endCropRect != .zero {
            offset = geometry.offset(for: endCropRect, scale: scale)
        } else {
            offset = phaseEndOffset
        }

        cropState = CropOverlayState(
            aspectRatio: cropState.aspectRatio,
            scale: scale,
            offset: offset
        )

        if let geometry {
            normalizeCropTransform(geometry: geometry)
        }
    }

    /// Called when the crop view lays out after returning from a later screen.
    func consumeEndTransformRestore(geometry: CropGeometry) {
        guard pendingEndTransformRestore, cropPhase == .end else { return }
        pendingEndTransformRestore = false
        restoreEndPhaseTransform(geometry: geometry)
    }

    func selectScrollDirection(_ direction: ScrollDirection) {
        guard cropPhase == .start else { return }
        scrollDirection = direction
    }

    /// Picks the movement axis during the start phase.
    func selectScrollAxis(_ axis: ScrollAxis) {
        guard cropPhase == .start else { return }
        guard scrollDirection?.scrollAxis != axis else { return }
        selectScrollDirection(axis.defaultDirection)
    }

    /// Checkmark in the start phase: lock the framed region, switch to the end.
    func confirmStartPhase(geometry: CropGeometry) {
        let cropRect = geometry.cropRectInImage(scale: cropState.scale, offset: cropState.offset)
        guard cropRect.width > 1, cropRect.height > 1 else {
            errorMessage = "Invalid selection. Please try again."
            return
        }
        confirmedCropRect = cropRect
        phaseStartOffset = cropState.offset
        phaseStartScale = cropState.scale
        cropState = CropOverlayState(
            aspectRatio: cropState.aspectRatio,
            scale: phaseStartScale,
            offset: phaseStartOffset
        )
        cropPhase = .end
    }

    /// Checkmark in the end phase: capture the end position and continue.
    func confirmEndPhase(geometry: CropGeometry) {
        guard scrollDirection != nil else { return }
        let endRect = geometry.cropRectInImage(scale: cropState.scale, offset: cropState.offset)
        if Self.cropRectsAreEffectivelyEqual(confirmedCropRect, endRect) {
            errorMessage = "The start and end positions must be different. Move the picture around."
            return
        }
        endCropRect = endRect
        phaseEndOffset = cropState.offset
        phaseEndScale = cropState.scale
        // The viewport animates from the start framing to the end framing. The
        // pipeline direction is the way the viewport actually travels between
        // them, derived from their delta so playback always matches the framing.
        let direction = pipelineDirection(from: confirmedCropRect, to: endRect)
        screen = .frameRate
        prepareAnimation(direction: direction)
    }

    /// The direction the viewport travels from the start crop to the end crop.
    private func pipelineDirection(from start: CGRect, to end: CGRect) -> ScrollDirection {
        let axis = scrollDirection?.scrollAxis ?? .vertical
        switch axis {
        case .vertical:
            return (end.minY - start.minY) >= 0 ? .down : .up
        case .horizontal:
            return (end.minX - start.minX) >= 0 ? .right : .left
        }
    }

    private static func cropRectsAreEffectivelyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        let epsilon: CGFloat = 0.5
        return abs(a.origin.x - b.origin.x) < epsilon
            && abs(a.origin.y - b.origin.y) < epsilon
            && abs(a.width - b.width) < epsilon
            && abs(a.height - b.height) < epsilon
    }

    /// Locks end-phase panning to the chosen axis (the perpendicular axis stays
    /// at the start position) while allowing movement in either direction along
    /// it. The actual scroll direction is derived from the movement itself.
    func constrainedEndOffset(_ proposed: CGSize) -> CGSize {
        guard let direction = scrollDirection else { return proposed }
        switch direction.scrollAxis {
        case .vertical:
            return CGSize(width: phaseStartOffset.width, height: proposed.height)
        case .horizontal:
            return CGSize(width: proposed.width, height: phaseStartOffset.height)
        }
    }

    /// Updates the highlighted arrow to match the way the user is panning, so
    /// the arrow always reflects the resulting scroll direction. Movement of the
    /// photo shifts the captured region the opposite way, hence the inversion.
    private func updateEndDirection(for offset: CGSize) {
        guard let direction = scrollDirection else { return }
        let threshold: CGFloat = 1
        switch direction.scrollAxis {
        case .vertical:
            let dy = offset.height - phaseStartOffset.height
            if dy < -threshold {
                scrollDirection = .down
            } else if dy > threshold {
                scrollDirection = .up
            }
        case .horizontal:
            let dx = offset.width - phaseStartOffset.width
            if dx < -threshold {
                scrollDirection = .right
            } else if dx > threshold {
                scrollDirection = .left
            }
        }
    }

    func cancelFrameRate() {
        stopAnimation()
        cropPhase = .end
        pendingEndTransformRestore = true
        restoreEndPhaseTransform(geometry: nil)
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
        let brightnessValue = brightness
        let mode = playbackMode
        let selected = min(max(minFrameCount, frameCount), maxFrameCount)
        let processor = ImageProcessor()

        Task {
            let rendered = await Task.detached(priority: .userInitiated) {
                processor.renderScrollAnimation(
                    from: source,
                    algorithm: algorithm,
                    contrast: contrastValue,
                    brightness: brightnessValue,
                    playbackMode: mode
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
        let brightnessValue = brightness
        let processor = ImageProcessor()

        stillRenderTask = Task {
            let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let cgImage = processor.renderStrip(
                    from: source,
                    algorithm: algorithm,
                    contrast: contrastValue,
                    brightness: brightnessValue
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
        playbackMode = .bounce
        contrast = 0
        brightness = 0
        stillPreview = nil
        stillRenderTask?.cancel()
        cropPhase = .start
        endCropRect = .zero
        phaseEndOffset = .zero
        phaseEndScale = 1.0
        pendingEndTransformRestore = false
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
        goToCrop()
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
                    goToCrop()
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
                pendingEndTransformRestore = true
                restoreEndPhaseTransform(geometry: nil)
                screen = .crop
                return
            }

            scrollAnimationSource = source

            let mode = playbackMode
            let generated = await Task.detached(priority: .userInitiated) {
                processor.renderScrollAnimation(from: source, algorithm: algorithm, playbackMode: mode)
            }.value

            fullCgFrames = generated
            maxFrameCount = generated.count
            frameCount = defaultFrameCount(maxAvailable: generated.count)
            isPreparingFrames = false

            if generated.isEmpty {
                errorMessage = "Could not generate animation."
                cropPhase = .end
                pendingEndTransformRestore = true
                restoreEndPhaseTransform(geometry: nil)
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
            rerenderPreviewAnimation()
        default:
            break
        }
    }

    /// Switches between bounce and loop playback, re-rendering the live preview.
    func selectPlaybackMode(_ mode: PlaybackMode) {
        guard mode != playbackMode else { return }
        playbackMode = mode
        guard screen == .preview, scrollAnimationSource != nil else { return }
        rerenderPreviewAnimation()
    }

    private func rerenderPreviewAnimation() {
        guard let source = scrollAnimationSource else { return }

        stopAnimation()
        isReprocessingDither = true
        gifData = nil

        let algorithm = ditherAlgorithm
        let contrastValue = contrast
        let brightnessValue = brightness
        let mode = playbackMode
        let selectedFrameCount = min(max(minFrameCount, frameCount), maxFrameCount)
        let processor = ImageProcessor()

        Task {
            let rendered = await Task.detached(priority: .userInitiated) {
                processor.renderScrollAnimation(
                    from: source,
                    algorithm: algorithm,
                    contrast: contrastValue,
                    brightness: brightnessValue,
                    playbackMode: mode
                )
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
    /// Picks 100 frames when the animation has at least that many; otherwise the
    /// maximum available (closest value to the sweet spot).
    private func defaultFrameCount(maxAvailable: Int) -> Int {
        guard maxAvailable > 0 else { return 0 }
        return min(max(minFrameCount, sweetSpotFrameCount), maxAvailable)
    }

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
    /// presenting the paywall first when no free exports remain. On success the
    /// GIF is also added to the app's gallery.
    func saveGIF(unlocked: Bool, gallery: GalleryStore) async {
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

        do {
            try await PhotoLibrarySaver.saveGIF(data)
            gifData = data
            gallery.add(data: data, resolution: resolution)
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
        resolution = LEDResolution(height: height, width: width)
        if resolution.isValid {
            var state = cropState
            state.aspectRatio = resolution.aspectRatio
            cropState = state
        }
    }

    /// Fills empty fields with defaults when editing finishes. Out-of-range values
    /// are left as typed so the inline validation message stays visible.
    func normalizeResolutionText() {
        if heightText.filter(\.isNumber).isEmpty {
            heightText = String(LEDResolution.default.height)
        }
        if widthText.filter(\.isNumber).isEmpty {
            widthText = String(LEDResolution.default.width)
        }
        syncResolutionFromText()
        if resolution.isValid {
            resolution.save()
        }
    }

    /// Applies a clamped crop transform from the crop view's gestures.
    func updateCropTransform(scale: CGFloat, offset: CGSize, geometry: CropGeometry) {
        guard geometry.isValid else { return }
        var state = cropState
        state.scale = geometry.clampedScale(scale)
        let constrained = cropPhase == .end ? constrainedEndOffset(offset) : offset
        state.offset = geometry.clampedOffset(scale: state.scale, offset: constrained)
        cropState = state

        if cropPhase == .end {
            updateEndDirection(for: state.offset)
        }
    }

    /// Re-clamps the current transform to a (possibly new) layout.
    func normalizeCropTransform(geometry: CropGeometry) {
        updateCropTransform(scale: cropState.scale, offset: cropState.offset, geometry: geometry)
    }
}

// MARK: - Crop overlay state

/// Transform of the photo under a fixed, centered selection frame.
///
/// The frame never moves: the user zooms (pinch) and pans the photo beneath it.
/// `scale` is relative to the photo's fitted size (1 = photo fills the crop area)
/// and `offset` translates the photo's center, in points, within the crop area.
struct CropOverlayState {
    var aspectRatio: CGFloat = LEDResolution.default.aspectRatio
    var scale: CGFloat = 1.0
    var offset: CGSize = .zero

    mutating func reset(for aspectRatio: CGFloat) {
        self.aspectRatio = aspectRatio
        scale = 1.0
        offset = .zero
    }
}

// MARK: - Crop geometry

/// Pure layout math for the fixed-frame crop UI. Built fresh from the current
/// layout so the view and the view model always agree on where the photo, the
/// selection frame, and the captured pixels are.
struct CropGeometry {
    /// On-screen area the photo occupies at `scale == 1` (also the clip bounds).
    let containerSize: CGSize
    /// Source image size in pixels (CGImage dimensions).
    let imagePixelSize: CGSize
    /// Selection frame aspect ratio (LED width / height).
    let aspectRatio: CGFloat
    /// Target LED resolution, used to cap zoom at one source pixel per LED pixel.
    let resolution: LEDResolution
    /// Empty space kept between the frame and the photo edges at `scale == 1`.
    let marginFraction: CGFloat
    /// Vertical position of the frame's center as a fraction of the crop-area
    /// height (0 = top, 0.5 = centered, 1 = bottom). Clamped so the frame keeps
    /// the margin at the top and bottom edges.
    let frameCenterFractionY: CGFloat

    init(
        containerSize: CGSize,
        imagePixelSize: CGSize,
        aspectRatio: CGFloat,
        resolution: LEDResolution,
        marginFraction: CGFloat = 0.08,
        frameCenterFractionY: CGFloat = 0.5
    ) {
        self.containerSize = containerSize
        self.imagePixelSize = imagePixelSize
        self.aspectRatio = aspectRatio
        self.resolution = resolution
        self.marginFraction = marginFraction
        self.frameCenterFractionY = frameCenterFractionY
    }

    var isValid: Bool {
        containerSize.width > 0 && containerSize.height > 0 &&
        imagePixelSize.width > 0 && imagePixelSize.height > 0 &&
        aspectRatio > 0
    }

    /// The fixed selection frame, both horizontally and vertically centered in
    /// the crop area (see `frameCenterFractionY`), keeping the margin at top and
    /// bottom.
    var frame: CGRect {
        guard isValid else { return .zero }
        let containerAspect = containerSize.width / containerSize.height
        var w: CGFloat
        var h: CGFloat
        if aspectRatio > containerAspect {
            w = containerSize.width * (1 - 2 * marginFraction)
            h = w / aspectRatio
        } else {
            h = containerSize.height * (1 - 2 * marginFraction)
            w = h * aspectRatio
        }
        let minY = containerSize.height * marginFraction
        let maxY = containerSize.height * (1 - marginFraction) - h
        let desiredY = containerSize.height * frameCenterFractionY - h / 2
        let y = min(max(desiredY, minY), max(minY, maxY))
        return CGRect(
            x: (containerSize.width - w) / 2,
            y: y,
            width: w,
            height: h
        )
    }

    /// Smallest scale at which the photo still fully covers the frame.
    var minScale: CGFloat {
        guard isValid else { return 1 }
        let f = frame
        return max(f.width / containerSize.width, f.height / containerSize.height)
    }

    /// Scale at which exactly the LED resolution of source pixels fits the frame
    /// (one source pixel per LED pixel). Zooming further would show fewer pixels.
    var resolutionLimitScale: CGFloat {
        guard isValid, resolution.width > 0 else { return minScale }
        return frame.width * imagePixelSize.width
            / (containerSize.width * CGFloat(resolution.width))
    }

    /// Largest scale the user may reach, never below `minScale`.
    var maxScale: CGFloat {
        max(minScale, resolutionLimitScale)
    }

    /// True when even fully zoomed out the frame holds fewer source pixels than
    /// the LED resolution, so the result will be upscaled (a quality warning).
    var photoBelowResolution: Bool {
        guard isValid else { return false }
        return resolutionLimitScale < minScale - 0.0001
    }

    func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minScale), maxScale)
    }

    /// The displayed photo rectangle for a given transform, in crop-area points.
    func photoRect(scale: CGFloat, offset: CGSize) -> CGRect {
        let size = CGSize(width: containerSize.width * scale, height: containerSize.height * scale)
        let center = CGPoint(
            x: containerSize.width / 2 + offset.width,
            y: containerSize.height / 2 + offset.height
        )
        return CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Clamps the offset so the photo always fully covers the selection frame.
    /// The photo is centered on the crop area plus `offset`, while the frame may
    /// sit off-center, so the allowed range is asymmetric.
    func clampedOffset(scale: CGFloat, offset: CGSize) -> CGSize {
        guard isValid else { return .zero }
        let f = frame
        let photoW = containerSize.width * scale
        let photoH = containerSize.height * scale
        let centerX = containerSize.width / 2
        let centerY = containerSize.height / 2

        // offset range that keeps the photo covering the frame on each axis.
        let lowerX = f.maxX - photoW / 2 - centerX
        let upperX = f.minX + photoW / 2 - centerX
        let lowerY = f.maxY - photoH / 2 - centerY
        let upperY = f.minY + photoH / 2 - centerY

        return CGSize(
            width: clamp(offset.width, lowerX, upperX),
            height: clamp(offset.height, lowerY, upperY)
        )
    }

    /// Clamps `value` into `[lower, upper]`, falling back to the midpoint if the
    /// range is inverted (photo smaller than the frame on that axis).
    private func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        guard lower <= upper else { return (lower + upper) / 2 }
        return min(max(value, lower), upper)
    }

    /// The pixels under the frame, in source-image pixel coordinates.
    func cropRectInImage(scale: CGFloat, offset: CGSize) -> CGRect {
        guard isValid else { return .zero }
        let photo = photoRect(scale: scale, offset: offset)
        guard photo.width > 0, photo.height > 0 else { return .zero }
        let f = frame

        let relative = CGRect(
            x: (f.minX - photo.minX) / photo.width,
            y: (f.minY - photo.minY) / photo.height,
            width: f.width / photo.width,
            height: f.height / photo.height
        )
        let pixelRect = CGRect(
            x: relative.minX * imagePixelSize.width,
            y: relative.minY * imagePixelSize.height,
            width: relative.width * imagePixelSize.width,
            height: relative.height * imagePixelSize.height
        )
        return pixelRect.intersection(CGRect(origin: .zero, size: imagePixelSize))
    }

    /// Inverse of `cropRectInImage`: finds the pan offset that places `cropRect`
    /// under the selection frame at the given zoom level.
    func offset(for cropRect: CGRect, scale: CGFloat) -> CGSize {
        guard isValid else { return .zero }
        let photoW = containerSize.width * scale
        let photoH = containerSize.height * scale
        guard photoW > 0, photoH > 0 else { return .zero }

        let f = frame
        let photoMinX = f.minX - cropRect.minX * photoW / imagePixelSize.width
        let photoMinY = f.minY - cropRect.minY * photoH / imagePixelSize.height
        let centerX = photoMinX + photoW / 2
        let centerY = photoMinY + photoH / 2

        return clampedOffset(
            scale: scale,
            offset: CGSize(
                width: centerX - containerSize.width / 2,
                height: centerY - containerSize.height / 2
            )
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
