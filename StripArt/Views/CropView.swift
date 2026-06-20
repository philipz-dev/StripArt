import SwiftUI

struct CropView: View {
    @ObservedObject var viewModel: StripArtViewModel

    @State private var imageDisplayRect: CGRect = .zero
    @State private var imagePixelSize: CGSize = .zero
    @State private var dragStartCenter: CGPoint?
    @State private var pinchStartScale: CGFloat?
    @State private var scaleStart: (scale: CGFloat, distance: CGFloat)?

    /// Vertical space reserved for the top controls and bottom action buttons,
    /// so the photo never sits underneath them.
    private let topReserved: CGFloat = 150
    private let bottomReserved: CGFloat = 130

    private let cropSpace = "cropArea"

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if let image = viewModel.sourceImage {
                    cropContent(image: image, containerSize: geometry.size)
                }

                overlayControls
            }
            .coordinateSpace(name: cropSpace)
        }
        .navigationBarHidden(true)
    }

    @ViewBuilder
    private func cropContent(image: UIImage, containerSize: CGSize) -> some View {
        let fitted = aspectFitRect(imageSize: image.size, in: containerSize)

        ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(width: fitted.width, height: fitted.height)
                .position(x: fitted.midX, y: fitted.midY)
                .allowsHitTesting(false)

            CropOverlayView(
                overlayRect: viewModel.cropState.overlayRect(in: fitted.size)
            )
            .frame(width: fitted.width, height: fitted.height)
            .position(x: fitted.midX, y: fitted.midY)
            .allowsHitTesting(false)

            if viewModel.cropPhase == .end, let direction = viewModel.scrollDirection {
                let overlay = viewModel.cropState.overlayRect(in: fitted.size)
                DirectionMoveArrow(direction: direction)
                    .position(
                        x: fitted.minX + overlay.midX,
                        y: fitted.minY + overlay.midY
                    )
                    .allowsHitTesting(false)
            }

            Color.clear
                .frame(width: fitted.width, height: fitted.height)
                .position(x: fitted.midX, y: fitted.midY)
                .contentShape(Rectangle())
                .gesture(dragGesture(in: fitted))
                .simultaneousGesture(pinchGesture(in: fitted))

            // Corner handles for resizing (start phase only).
            if viewModel.cropPhase == .start {
                let overlay = viewModel.cropState.overlayRect(in: fitted.size)
                ForEach(Array(corners(of: overlay).enumerated()), id: \.offset) { _, corner in
                    cornerHandle
                        .position(x: fitted.minX + corner.x, y: fitted.minY + corner.y)
                        .gesture(scaleGesture(in: fitted))
                }
            }
        }
        .onAppear {
            updateLayout(image: image, containerSize: containerSize)
        }
        .onChange(of: containerSize.width) {
            updateLayout(image: image, containerSize: containerSize)
        }
        .onChange(of: containerSize.height) {
            updateLayout(image: image, containerSize: containerSize)
        }
    }

    private var overlayControls: some View {
        VStack {
            topControls
                .padding(.top, 60)

            Spacer()

            HStack {
                Button {
                    viewModel.cancelCrop()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(
                    CircleIconButtonStyle(
                        gradient: BrandStyle.red,
                        shadowColor: BrandStyle.redShadow,
                        diameter: 62,
                        iconSize: 24
                    )
                )

                Spacer()

                Button {
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
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(
                    CircleIconButtonStyle(
                        gradient: BrandStyle.green,
                        shadowColor: BrandStyle.greenShadow,
                        diameter: 62,
                        iconSize: 24
                    )
                )
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    private var topControls: some View {
        VStack(spacing: 16) {
            Text(viewModel.cropPhase == .start ? "Choose start size & position" : "Choose end position")
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .shadow(radius: 4)

            HStack(spacing: 14) {
                ForEach(ScrollDirection.allCases) { direction in
                    directionArrow(direction)
                }
            }
        }
        .padding(.horizontal, 24)
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
                gradient: selected ? BrandStyle.blue : BrandStyle.glass,
                shadowColor: selected ? BrandStyle.blueShadow : .black,
                foreground: selected ? .white : .white.opacity(0.9),
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

    private func updateLayout(image: UIImage, containerSize: CGSize) {
        let fitted = aspectFitRect(imageSize: image.size, in: containerSize)
        imageDisplayRect = fitted
        if let cgImage = image.cgImage {
            imagePixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        } else {
            imagePixelSize = image.size
        }
        viewModel.clampCropState(in: fitted.size)
    }

    private func aspectFitRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }

        // Fit the photo into the region between the top controls and bottom buttons.
        let availableHeight = max(1, containerSize.height - topReserved - bottomReserved)
        let availableWidth = containerSize.width

        let widthRatio = availableWidth / imageSize.width
        let heightRatio = availableHeight / imageSize.height
        let scale = min(widthRatio, heightRatio)

        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (containerSize.width - size.width) / 2,
            y: topReserved + (availableHeight - size.height) / 2
        )
        return CGRect(origin: origin, size: size)
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
