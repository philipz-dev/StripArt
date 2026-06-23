import SwiftUI

struct CropView: View {
    @ObservedObject var viewModel: StripArtViewModel

    @AppStorage("hideCropTips") private var hideCropTips = false

    /// Crop-area size (fitted photo) and source pixels, measured from layout.
    @State private var cropAreaSize: CGSize = .zero
    @State private var imagePixelSize: CGSize = .zero

    /// Gesture anchors.
    @State private var pinchStartScale: CGFloat?
    @State private var pinchStartOffset: CGSize?
    @State private var dragStartOffset: CGSize?

    private let marginFraction: CGFloat = 0.08

    var body: some View {
        VStack(spacing: 16) {
            topControls

            if let image = viewModel.sourceImage {
                cropArea(image: image)
            }

            footer

            DecisionButtons(
                confirmEnabled: stateGeometry?.isValid ?? false,
                cancel: { viewModel.cancelCrop() },
                confirm: { confirmPhase() }
            )
        }
        .padding(24)
        .navigationBarHidden(true)
    }

    // MARK: - Geometry

    /// Geometry built from the last committed layout, used for chrome and confirm.
    private var stateGeometry: CropGeometry? {
        makeGeometry(container: cropAreaSize)
    }

    private func makeGeometry(container: CGSize) -> CropGeometry? {
        guard container.width > 0, container.height > 0,
              imagePixelSize.width > 0, imagePixelSize.height > 0 else {
            return nil
        }
        return CropGeometry(
            containerSize: container,
            imagePixelSize: imagePixelSize,
            aspectRatio: viewModel.resolution.aspectRatio,
            resolution: viewModel.resolution,
            marginFraction: marginFraction
        )
    }

    // MARK: - Crop area

    private func cropArea(image: UIImage) -> some View {
        GeometryReader { geo in
            let fitted = fittedSize(for: image, in: geo.size)
            let g = CropGeometry(
                containerSize: fitted,
                imagePixelSize: pixelSize(of: image),
                aspectRatio: viewModel.resolution.aspectRatio,
                resolution: viewModel.resolution,
                marginFraction: marginFraction
            )
            let photo = g.photoRect(scale: viewModel.cropState.scale, offset: viewModel.cropState.offset)

            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: photo.width, height: photo.height)
                    .position(x: photo.midX, y: photo.midY)

                CropFrameOverlay(frameRect: g.frame)
                    .allowsHitTesting(false)

                Picture3DBorder()
                    .frame(width: g.frame.width, height: g.frame.height)
                    .position(x: g.frame.midX, y: g.frame.midY)
                    .allowsHitTesting(false)

                if viewModel.cropPhase == .end, let direction = viewModel.scrollDirection {
                    DirectionMoveArrow(direction: direction)
                        .position(x: g.frame.midX, y: g.frame.midY)
                        .allowsHitTesting(false)
                }

                Color.clear
                    .frame(width: fitted.width, height: fitted.height)
                    .contentShape(Rectangle())
                    .gesture(combinedGesture(geometry: g))
            }
            .frame(width: fitted.width, height: fitted.height)
            .clipped()
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { commitContainer(fitted, image: image) }
            .onChange(of: fitted) { _, newValue in commitContainer(newValue, image: image) }
            .onChange(of: viewModel.resolution) { _, _ in commitContainer(fitted, image: image) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Chrome

    private var topControls: some View {
        VStack(spacing: 14) {
            Text(viewModel.cropPhase == .start ? "Define Starting View" : "Define Ending View")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(BrandStyle.blue)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            HStack(spacing: 14) {
                ForEach(ScrollDirection.allCases) { direction in
                    directionArrow(direction)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 10) {
            if !hideCropTips {
                tipBanner
            }
            if stateGeometry?.photoBelowResolution == true {
                warningBanner
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: hideCropTips)
    }

    private var tipBanner: some View {
        let text = viewModel.cropPhase == .start
            ? "Pinch to zoom · drag to move the photo. The frame is your LED strip."
            : "Drag the photo to set where the animation ends."
        return Label(text, systemImage: "hand.draw")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(
                Capsule(style: .continuous).fill(Color.black.opacity(0.05))
            )
    }

    private var warningBanner: some View {
        Label(
            "This photo has fewer pixels than your LED resolution, so the result may look soft.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption.weight(.medium))
        .foregroundStyle(Color(red: 0.78, green: 0.45, blue: 0.05))
        .multilineTextAlignment(.center)
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(
            Capsule(style: .continuous).fill(Color(red: 1.0, green: 0.85, blue: 0.45).opacity(0.25))
        )
    }

    private func directionArrow(_ direction: ScrollDirection) -> some View {
        let selected = viewModel.scrollDirection == direction
        return Button {
            viewModel.selectScrollDirection(direction)
        } label: {
            Image(systemName: direction.systemImageName)
        }
        .buttonStyle(
            CircleIconButtonStyle(
                gradient: selected ? BrandStyle.blue : BrandStyle.neutral,
                shadowColor: selected ? BrandStyle.blueShadow : .black,
                foreground: selected ? .white : .primary,
                diameter: 50,
                iconSize: 19,
                strokeOpacity: selected ? 0.55 : 0.3
            )
        )
    }

    // MARK: - Gestures

    private func combinedGesture(geometry g: CropGeometry) -> some Gesture {
        let drag = DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Ignore drags while pinching — simultaneous recognition would
                // fight the pinch and make the photo jump.
                guard pinchStartScale == nil else { return }
                if dragStartOffset == nil {
                    dragStartOffset = viewModel.cropState.offset
                }
                guard let start = dragStartOffset else { return }
                let proposed = CGSize(
                    width: start.width + value.translation.width,
                    height: start.height + value.translation.height
                )
                viewModel.updateCropTransform(
                    scale: viewModel.cropState.scale,
                    offset: proposed,
                    geometry: g
                )
            }
            .onEnded { _ in
                dragStartOffset = nil
                dismissTip()
            }

        let pinch = MagnificationGesture()
            .onChanged { value in
                // Zoom only while choosing the start framing; the end phase keeps
                // the exact same scale so there is no jump between phases.
                guard viewModel.cropPhase == .start else { return }
                if pinchStartScale == nil {
                    pinchStartScale = viewModel.cropState.scale
                    pinchStartOffset = viewModel.cropState.offset
                }
                guard let startScale = pinchStartScale,
                      let startOffset = pinchStartOffset else { return }

                let newScale = g.clampedScale(startScale * value)
                let ratio = newScale / max(startScale, 0.0001)
                // Zoom about the frame centre (coincides with the crop-area centre):
                // scale the pan offset from its value at pinch-start, never compound
                // per frame or the photo lurches.
                let proposedOffset = CGSize(
                    width: startOffset.width * ratio,
                    height: startOffset.height * ratio
                )
                viewModel.updateCropTransform(
                    scale: newScale,
                    offset: proposedOffset,
                    geometry: g
                )
            }
            .onEnded { _ in
                pinchStartScale = nil
                pinchStartOffset = nil
                dismissTip()
            }

        return drag.simultaneously(with: pinch)
    }

    // MARK: - Helpers

    private func commitContainer(_ size: CGSize, image: UIImage) {
        guard size.width > 0, size.height > 0 else { return }
        cropAreaSize = size
        imagePixelSize = pixelSize(of: image)
        if let g = makeGeometry(container: size) {
            viewModel.normalizeCropTransform(geometry: g)
        }
    }

    private func confirmPhase() {
        guard let g = stateGeometry else { return }
        if viewModel.cropPhase == .start {
            viewModel.confirmStartPhase(geometry: g)
        } else {
            viewModel.confirmEndPhase(geometry: g)
        }
        dismissTip()
    }

    private func dismissTip() {
        if !hideCropTips { hideCropTips = true }
    }

    private func pixelSize(of image: UIImage) -> CGSize {
        if let cg = image.cgImage {
            return CGSize(width: cg.width, height: cg.height)
        }
        return image.size
    }

    private func fittedSize(for image: UIImage, in available: CGSize) -> CGSize {
        guard image.size.width > 0, image.size.height > 0,
              available.width > 0, available.height > 0 else {
            return available
        }
        let imageAspect = image.size.width / image.size.height
        let availableAspect = available.width / available.height
        if imageAspect > availableAspect {
            return CGSize(width: available.width, height: available.width / imageAspect)
        } else {
            return CGSize(width: available.height * imageAspect, height: available.height)
        }
    }
}

/// Dims everything outside the fixed selection frame. The visible edge of the
/// frame itself is drawn separately by `Picture3DBorder`.
private struct CropFrameOverlay: View {
    let frameRect: CGRect

    var body: some View {
        Canvas { context, size in
            var path = Path(CGRect(origin: .zero, size: size))
            path.addRect(frameRect)
            context.fill(path, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
        }
    }
}

/// Thick, semi-transparent arrow shown over the crop frame in the end phase to
/// indicate which way the photo should be dragged.
private struct DirectionMoveArrow: View {
    let direction: ScrollDirection

    var body: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: 70, weight: .black))
            .foregroundStyle(.white.opacity(0.65))
            .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 2)
            .rotationEffect(rotation)
    }

    private var rotation: Angle {
        switch direction {
        case .up: .degrees(0)
        case .right: .degrees(90)
        case .down: .degrees(180)
        case .left: .degrees(270)
        }
    }
}
