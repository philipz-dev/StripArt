import SwiftUI

struct PreviewView: View {
    @ObservedObject var viewModel: StripArtViewModel
    @ObservedObject var store: StoreManager
    @ObservedObject var gallery: GalleryStore
    @State private var shareItem: ShareGIFItem?

    var body: some View {
        GeometryReader { geometry in
            let previewMaxHeight = Self.previewMaxHeight(
                in: geometry.size,
                showsDirection: viewModel.scrollDirection != nil,
                showsExportStatus: !store.isUnlocked,
                showsShareButton: !needsUnlock
            )

            VStack(spacing: 16) {
                header

                simulationBlock(maxHeight: previewMaxHeight)

                Spacer(minLength: 0)

                actionButtons
            }
            .padding(24)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .navigationBarHidden(true)
        .sheet(item: $shareItem) { item in
            ActivityShareSheet(items: [item.url])
        }
    }

    /// LED preview, metadata, and playback controls stay grouped so the buttons
    /// sit directly beneath the animation regardless of its rendered size.
    private func simulationBlock(maxHeight: CGFloat) -> some View {
        VStack(spacing: 12) {
            previewArea(maxHeight: maxHeight)

            if let direction = viewModel.scrollDirection {
                Text("Direction: \(direction.label) · \(viewModel.resolution.height)×\(viewModel.resolution.width) px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
            }

            playbackSection
        }
    }

    private static func previewMaxHeight(
        in size: CGSize,
        showsDirection: Bool,
        showsExportStatus: Bool,
        showsShareButton: Bool
    ) -> CGFloat {
        let verticalPadding: CGFloat = 48
        let headerBlock: CGFloat = 78
        let directionLine: CGFloat = showsDirection ? 20 : 0
        let playbackBlock: CGFloat = 72
        let sectionSpacing: CGFloat = 12 * 2 + 16
        let exportStatus: CGFloat = showsExportStatus ? 44 : 0
        let primaryActions: CGFloat = 48
        let shareAction: CGFloat = showsShareButton ? 60 : 0
        let actionSpacing: CGFloat = 12 * (showsShareButton ? 2 : 1)

        let reserved = verticalPadding
            + headerBlock
            + directionLine
            + playbackBlock
            + sectionSpacing
            + exportStatus
            + primaryActions
            + shareAction
            + actionSpacing

        return max(72, size.height - reserved)
    }

    private var header: some View {
        VStack(spacing: 10) {
            ScreenTitle(title: "LED simulation")
            Text("Pixel-perfect preview at LED resolution")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func previewArea(maxHeight: CGFloat) -> some View {
        ZStack {
            Color.black

            if viewModel.isProcessing || viewModel.isReprocessingDither {
                ProgressView(viewModel.isReprocessingDither ? "Applying dither…" : "Processing…")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else if !viewModel.frames.isEmpty,
                      let cgFrame = viewModel.frames[viewModel.currentFrameIndex].cgImage {
                LEDBarView(image: cgFrame)
            }
        }
        // Apply the aspect ratio to the whole stack so the black backdrop, the
        // image, and the border all share the exact same rectangle — they line
        // up for any resolution, including portrait ones.
        .aspectRatio(viewModel.resolution.aspectRatio, contentMode: .fit)
        .overlay(Picture3DBorder())
        .frame(maxWidth: .infinity)
        .frame(maxHeight: maxHeight)
    }

    private var playbackSection: some View {
        HStack(spacing: 16) {
            alignedPlaybackButton(for: .bounce)
            alignedPlaybackButton(for: .loop)
        }
    }

    private func alignedPlaybackButton(for mode: PlaybackMode) -> some View {
        HStack {
            Spacer(minLength: 0)
            PlaybackChoiceButton(
                mode: mode,
                isSelected: viewModel.playbackMode == mode
            ) {
                viewModel.selectPlaybackMode(mode)
            }
            .disabled(viewModel.isProcessing || viewModel.isReprocessingDither)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            ExportAllowanceView(
                store: store,
                remaining: viewModel.remainingFreeExports,
                limit: viewModel.freeExportLimit,
                compact: true
            )

            HStack(spacing: 16) {
                Button(role: .cancel) {
                    viewModel.cancelPreview()
                } label: {
                    Text("Back")
                }
                .buttonStyle(
                    GradientButtonStyle(
                        gradient: BrandStyle.neutral,
                        shadowColor: .black,
                        foreground: .primary
                    )
                )

                Button {
                    saveOrPrompt()
                } label: {
                    if viewModel.isSaving || store.purchaseInProgress {
                        ProgressView()
                            .tint(.white)
                    } else if needsUnlock {
                        Text("Unlock for \(store.displayPrice)")
                    } else {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                }
                .buttonStyle(GradientButtonStyle())
                .disabled(viewModel.isProcessing || viewModel.isReprocessingDither || viewModel.frames.isEmpty || viewModel.isSaving || store.purchaseInProgress)
            }

            if !needsUnlock {
                Button {
                    prepareShare()
                } label: {
                    Label("Share / Save to Files", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(
                    GradientButtonStyle(
                        gradient: BrandStyle.neutral,
                        shadowColor: .black,
                        foreground: .primary
                    )
                )
                .disabled(viewModel.gifData == nil || viewModel.isProcessing || viewModel.isReprocessingDither)
            }
        }
    }

    private var needsUnlock: Bool {
        !store.isUnlocked && !viewModel.hasFreeExportsLeft
    }

    private func saveOrPrompt() {
        if store.isUnlocked || viewModel.hasFreeExportsLeft {
            Task { await viewModel.saveGIF(unlocked: store.isUnlocked, gallery: gallery) }
        } else {
            store.purchaseError = nil
            viewModel.showPaywall = true
        }
    }

    private func prepareShare() {
        guard let data = viewModel.gifData else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StripArt-\(UUID().uuidString).gif")
        do {
            try data.write(to: url)
            shareItem = ShareGIFItem(url: url)
        } catch {
            viewModel.errorMessage = "Could not prepare the file."
        }
    }
}

/// Compact square bounce/loop toggle for the LED simulation screen.
private struct PlaybackChoiceButton: View {
    let mode: PlaybackMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: mode.systemImageName)
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .rotationEffect(.degrees(90))

                Text(mode.label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(width: 72, height: 72)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? BrandStyle.blue : BrandStyle.neutral)
                    if isSelected {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.28), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isSelected ? .white.opacity(0.25) : .black.opacity(0.08),
                            lineWidth: 1
                        )
                }
            )
            .shadow(
                color: (isSelected ? BrandStyle.blueShadow : .black).opacity(isSelected ? 0.30 : 0.10),
                radius: isSelected ? 5 : 3,
                x: 0,
                y: isSelected ? 3 : 2
            )
        }
        .buttonStyle(PlaybackPushButtonStyle())
    }
}

private struct PlaybackPushButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct ShareGIFItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
