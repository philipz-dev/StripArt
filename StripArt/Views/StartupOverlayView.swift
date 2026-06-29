import AVFoundation
import SwiftUI

/// Full-screen intro shown on launch: loops the startup video until the user taps.
struct StartupOverlayView: View {
    let onDismiss: () -> Void

    private let videoAspect: CGFloat = 853.0 / 1844.0

    var body: some View {
        GeometryReader { geometry in
            let videoWidth = min(geometry.size.width, geometry.size.height * videoAspect)
            let videoHeight = min(geometry.size.height, geometry.size.width / videoAspect)

            ZStack {
                startupBackground

                ZStack {
                    LoopingVideoView(resourceName: "startup-animation")
                        .accessibilityHidden(true)

                    VStack(spacing: 0) {
                        StartupHeadlineText(
                            "Easily convert your pictures to stunning LED animations!",
                            width: videoWidth
                        )
                        .padding(.top, videoHeight * 0.105)

                        Spacer(minLength: 0)
                    }
                    .frame(width: videoWidth, height: videoHeight)

                    VStack(spacing: 0) {
                        Text("Select frame:")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundStyle(BrandStyle.blue)
                            .frame(maxWidth: videoWidth * 0.58)
                            .padding(.top, videoHeight * 0.285)

                        Spacer(minLength: 0)
                    }
                    .frame(width: videoWidth, height: videoHeight)
                }
                .frame(width: videoWidth, height: videoHeight)
                .clipShape(RoundedRectangle(cornerRadius: 0))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
        }
        .ignoresSafeArea()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("StripArt introduction. Double tap to continue.")
    }

    private var startupBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.72, green: 0.85, blue: 0.97),
                    Color(red: 0.93, green: 0.96, blue: 1.0),
                    Color(red: 0.97, green: 0.98, blue: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [Color(red: 0.36, green: 0.68, blue: 1.0).opacity(0.35), .clear],
                center: .init(x: 0.5, y: 0.18),
                startRadius: 0,
                endRadius: 280
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Headline

private struct StartupHeadlineText: View {
    let text: String
    let width: CGFloat

    private let outline = Color(red: 0.04, green: 0.22, blue: 0.65)
    private let font = Font.system(.title2, design: .rounded).weight(.bold)

    init(_ text: String, width: CGFloat) {
        self.text = text
        self.width = width
    }

    var body: some View {
        ZStack {
            Text(text)
                .font(font)
                .multilineTextAlignment(.center)
                .foregroundStyle(outline.opacity(0.55))
                .shadow(color: outline.opacity(0.5), radius: 0, x: -1, y: 0)
                .shadow(color: outline.opacity(0.5), radius: 0, x: 1, y: 0)
                .shadow(color: outline.opacity(0.5), radius: 0, x: 0, y: -1)
                .shadow(color: outline.opacity(0.5), radius: 0, x: 0, y: 1)

            Text(text)
                .font(font)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
        }
        .shadow(color: outline.opacity(0.22), radius: 10, y: 3)
        .padding(.horizontal, width * 0.07)
        .frame(width: width)
    }
}

// MARK: - Looping video

private struct LoopingVideoView: UIViewRepresentable {
    let resourceName: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView(player: nil)

        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4") else {
            return view
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        // Hold on the final frame at the end instead of clearing the layer, so
        // the manual seek-back below never exposes a blank (white) frame.
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false
        view.setPlayer(player)

        context.coordinator.player = player
        context.coordinator.endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                player.play()
            }
        }

        player.play()
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        if let observer = coordinator.endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        coordinator.player?.pause()
    }

    final class Coordinator {
        var player: AVPlayer?
        var endObserver: NSObjectProtocol?
    }
}

private final class PlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    init(player: AVPlayer?) {
        super.init(frame: .zero)
        backgroundColor = .clear
        playerLayer.backgroundColor = UIColor.clear.cgColor
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setPlayer(_ player: AVPlayer?) {
        playerLayer.player = player
    }

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

#Preview {
    StartupOverlayView(onDismiss: {})
}
