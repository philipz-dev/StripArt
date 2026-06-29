import SwiftUI

struct PreviewView: View {
    @ObservedObject var viewModel: StripArtViewModel
    @ObservedObject var store: StoreManager
    @ObservedObject var gallery: GalleryStore
    @State private var shareItem: ShareGIFItem?

    var body: some View {
        VStack(spacing: 24) {
            header

            previewArea

            if let direction = viewModel.scrollDirection {
                Text("Direction: \(direction.label) · \(viewModel.resolution.height)×\(viewModel.resolution.width) px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            actionButtons
        }
        .padding(24)
        .navigationBarHidden(true)
        .sheet(item: $shareItem) { item in
            ActivityShareSheet(items: [item.url])
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ScreenTitle(title: "Preview")
            Text("Pixel-perfect preview at LED resolution")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var previewArea: some View {
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
        .frame(maxWidth: .infinity, maxHeight: 280)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if !store.isUnlocked {
                FreeExportsStatusView(
                    remaining: viewModel.remainingFreeExports,
                    limit: viewModel.freeExportLimit,
                    compact: true
                )
            }

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
