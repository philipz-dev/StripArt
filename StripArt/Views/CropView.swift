import SwiftUI

struct CropView: View {
    @ObservedObject var viewModel: StripArtViewModel

    @State private var imageDisplayRect: CGRect = .zero
    @State private var imagePixelSize: CGSize = .zero
    @State private var dragStartCenter: CGPoint?
    @State private var pinchStartScale: CGFloat?
    @State private var scaleStart: (scale: CGFloat, distance: CGFloat)?

    private let cropSpace = "cropArea"

    var body: some View {
        VStack(spacing: 20) {
            topControls

            if let image = viewModel.sourceImage {
                HStack(spacing: 8) {
                    cropPicture(image: image)

                    if viewModel.cropPhase == .start {
                        zoomSlider
                    }
                }
            }

            DecisionButtons(
                cancel: { viewModel.cancelCrop() },
                confirm: { confirmPhase() }
            )
        }
        .padding(24)
        .navigationBarHidden(true)
    }

    /// The photo and all crop UI. In the start phase the photo itself is
    /// magnified by the zoom while the selection frame stays put; in the end
    /// phase the photo sits at its natural fit and the frame is drawn at the
    /// zoom-adjusted (effective) size so it grows/shrinks with the zoom.
    private func cropPicture(image: UIImage) -> some View {
        GeometryReader { geo in
            let display = fittedSize(for: image, in: geo.size)
            let isStart = viewModel.cropPhase == .start

            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: display.width, height: display.height)
                    .scaleEffect(
                        isStart ? max(1, viewModel.cropState.zoom) : 1,
                        anchor: UnitPoint(
                            x: viewModel.cropState.center.x,
                            y: viewModel.cropState.center.y
                        )
                    )
                    .clipped()

                cropOverlay(in: display)
            }
            .frame(width: display.width, height: display.height)
            .clipped()
            .overlay(Picture3DBorder())
            .coordinateSpace(name: cropSpace)
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { setDisplay(size: display, image: image) }
            .onChange(of: display) { _, newSize in
                setDisplay(size: newSize, image: image)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func cropOverlay(in size: CGSize) -> some View {
        let imageRect = CGRect(origin: .zero, size: size)
        let base = viewModel.cropState.overlayRect(in: size)
        let drawn = viewModel.cropPhase == .start
            ? base
            : viewModel.cropState.effectiveOverlayRect(in: size)

        ZStack {
            CropOverlayView(overlayRect: drawn)
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)

            if viewModel.cropPhase == .end, let direction = viewModel.scrollDirection {
                DirectionMoveArrow(direction: direction)
                    .position(x: drawn.midX, y: drawn.midY)
                    .allowsHitTesting(false)
            }

            Color.clear
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .gesture(dragGesture(in: imageRect))
                .simultaneousGesture(pinchGesture(in: imageRect))

            if viewModel.cropPhase == .start {
                ForEach(Array(corners(of: base).enumerated()), id: \.offset) { _, corner in
                    cornerHandle
                        .position(x: corner.x, y: corner.y)
                        .gesture(scaleGesture(in: imageRect))
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Vertical zoom slider: `+` on top, `−` at the bottom (min = start).
    private var zoomSlider: some View {
        let length: CGFloat = 180
        return VStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.headline.weight(.bold))
                .foregroundStyle(.secondary)

            Slider(
                value: zoomBinding,
                in: Double(CropOverlayState.minZoom)...Double(CropOverlayState.maxZoom)
            )
            .frame(width: length)
            .rotationEffect(.degrees(-90))
            .frame(width: 44, height: length)

            Image(systemName: "minus")
                .font(.headline.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 44)
    }

    private var zoomBinding: Binding<Double> {
        Binding(
            get: { Double(viewModel.cropState.zoom) },
            set: { newValue in
                let size = imageDisplayRect.size
                guard size.width > 0, size.height > 0 else { return }
                viewModel.mutateCropState(in: size) { state in
                    state.zoom = min(
                        max(CropOverlayState.minZoom, CGFloat(newValue)),
                        CropOverlayState.maxZoom
                    )
                }
            }
        )
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

    private var topControls: some View {
        VStack(spacing: 14) {
            Text(viewModel.cropPhase == .start ? "Choose start size & position" : "Drag to end position")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
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

    private var cornerHandle: some View {
        Circle()
            .fill(.white)
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(BrandStyle.blue, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
            .contentShape(Circle().inset(by: -18))
    }

    private func dragGesture(in imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartCenter == nil {
                    dragStartCenter = viewModel.cropState.center
                }
                guard let start = dragStartCenter else { return }
                let dx = value.translation.width / imageRect.width
                let dy = value.translation.height / imageRect.height
                let proposed = CGPoint(x: start.x + dx, y: start.y + dy)
                viewModel.mutateCropState(in: imageRect.size) { state in
                    state.center = viewModel.cropPhase == .end
                        ? viewModel.constrainedEndCenter(proposed)
                        : proposed
                }
            }
            .onEnded { _ in
                dragStartCenter = nil
            }
    }

    /// Resizes the selection by dragging a corner, scaling from the center.
    /// Coordinates are in the shared `cropArea` space, matching the handle positions.
    private func scaleGesture(in imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(cropSpace))
            .onChanged { value in
                let overlay = viewModel.cropState.overlayRect(in: imageRect.size)
                let center = CGPoint(
                    x: imageRect.minX + overlay.midX,
                    y: imageRect.minY + overlay.midY
                )

                if scaleStart == nil {
                    scaleStart = (
                        viewModel.cropState.scale,
                        max(1, distance(value.startLocation, center))
                    )
                }
                guard let scaleStart else { return }

                let newDistance = distance(value.location, center)
                let factor = newDistance / scaleStart.distance
                viewModel.mutateCropState(in: imageRect.size) { state in
                    state.scale = min(max(scaleStart.scale * factor, 0.15), 1.0)
                }
            }
            .onEnded { _ in
                scaleStart = nil
            }
    }

    private func corners(of rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func pinchGesture(in imageRect: CGRect) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                // Scaling is only allowed while choosing the start size.
                guard viewModel.cropPhase == .start else { return }
                if pinchStartScale == nil {
                    pinchStartScale = viewModel.cropState.scale
                }
                guard let start = pinchStartScale else { return }
                viewModel.mutateCropState(in: imageRect.size) { state in
                    state.scale = min(max(start * value, 0.15), 1.0)
                }
            }
            .onEnded { _ in
                pinchStartScale = nil
            }
    }

    private func setDisplay(size: CGSize, image: UIImage) {
        guard size.width > 0, size.height > 0 else { return }
        imageDisplayRect = CGRect(origin: .zero, size: size)
        if let cgImage = image.cgImage {
            imagePixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        } else {
            imagePixelSize = image.size
        }
        viewModel.clampCropState(in: size)
    }

    private func confirmPhase() {
        if viewModel.cropPhase == .start {
            viewModel.confirmStartPhase(
                imageDisplayRect: imageDisplayRect,
                imagePixelSize: imagePixelSize
            )
        } else {
            viewModel.confirmEndPhase(
                imageDisplayRect: imageDisplayRect,
                imagePixelSize: imagePixelSize
            )
        }
    }
}

private struct CropOverlayView: View {
    let overlayRect: CGRect

    var body: some View {
        Canvas { context, size in
            var path = Path(CGRect(origin: .zero, size: size))
            path.addRect(overlayRect)
            context.fill(path, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))

            let border = Path(overlayRect)
            context.stroke(border, with: .color(.white), lineWidth: 2)
        }
    }
}

/// Thick, semi-transparent arrow shown over the crop frame in the end phase to
/// indicate which way the frame should be dragged.
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
