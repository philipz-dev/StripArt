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
                cropPicture(image: image)
            }

            DecisionButtons(
                cancel: { viewModel.cancelCrop() },
                confirm: { confirmPhase() }
            )
        }
        .padding(24)
        .navigationBarHidden(true)
    }

    /// The photo laid out exactly like the photo-review picture (same modifiers,
    /// same border) so there is no jump moving between screens. All crop UI is
    /// overlaid on top, measured against the image's own bounds.
    private func cropPicture(image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    cropOverlay(in: geo.size)
                        .onAppear { setDisplay(size: geo.size, image: image) }
                        .onChange(of: geo.size) { _, newSize in
                            setDisplay(size: newSize, image: image)
                        }
                }
                .coordinateSpace(name: cropSpace)
            }
            .overlay(Picture3DBorder())
    }

    @ViewBuilder
    private func cropOverlay(in size: CGSize) -> some View {
        let imageRect = CGRect(origin: .zero, size: size)
        let overlay = viewModel.cropState.overlayRect(in: size)

        ZStack {
            CropOverlayView(overlayRect: overlay)
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)

            if viewModel.cropPhase == .end, let direction = viewModel.scrollDirection {
                DirectionMoveArrow(direction: direction)
                    .position(x: overlay.midX, y: overlay.midY)
                    .allowsHitTesting(false)
            }

            Color.clear
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .gesture(dragGesture(in: imageRect))
                .simultaneousGesture(pinchGesture(in: imageRect))

            if viewModel.cropPhase == .start {
                ForEach(Array(corners(of: overlay).enumerated()), id: \.offset) { _, corner in
                    cornerHandle
                        .position(x: corner.x, y: corner.y)
                        .gesture(scaleGesture(in: imageRect))
                }
            }
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
