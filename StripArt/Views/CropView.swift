import SwiftUI

struct CropView: View {
    @ObservedObject var viewModel: StripArtViewModel

    @State private var imageDisplayRect: CGRect = .zero
    @State private var imagePixelSize: CGSize = .zero
    @State private var dragStartCenter: CGPoint?
    @State private var pinchStartScale: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if let image = viewModel.sourceImage {
                    cropContent(image: image, containerSize: geometry.size)
                }

                overlayControls
            }
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

            Color.clear
                .frame(width: fitted.width, height: fitted.height)
                .position(x: fitted.midX, y: fitted.midY)
                .contentShape(Rectangle())
                .gesture(dragGesture(in: fitted))
                .simultaneousGesture(pinchGesture(in: fitted))
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
                transparentCircleButton(systemName: "xmark") {
                    viewModel.cancelCrop()
                }

                Spacer()

                transparentCircleButton(systemName: "checkmark") {
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
                .font(.title3.bold())
                .foregroundStyle(selected ? .white : .white.opacity(0.85))
                .frame(width: 48, height: 48)
                .background(
                    Circle().fill(selected ? Color.accentColor : Color.white.opacity(0.15))
                )
                .overlay(
                    Circle().stroke(.white.opacity(selected ? 0.9 : 0.35), lineWidth: selected ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func transparentCircleButton(
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
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

        let widthRatio = containerSize.width / imageSize.width
        let heightRatio = containerSize.height / imageSize.height
        let scale = min(widthRatio, heightRatio)

        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2
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

            let handleSize: CGFloat = 10
            for corner in [
                CGPoint(x: overlayRect.minX, y: overlayRect.minY),
                CGPoint(x: overlayRect.maxX, y: overlayRect.minY),
                CGPoint(x: overlayRect.minX, y: overlayRect.maxY),
                CGPoint(x: overlayRect.maxX, y: overlayRect.maxY)
            ] {
                let handle = CGRect(
                    x: corner.x - handleSize / 2,
                    y: corner.y - handleSize / 2,
                    width: handleSize,
                    height: handleSize
                )
                context.fill(Path(ellipseIn: handle), with: .color(.white))
            }
        }
    }
}
