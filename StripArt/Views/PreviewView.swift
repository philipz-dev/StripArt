import SwiftUI

struct PreviewView: View {
    @ObservedObject var viewModel: StripArtViewModel
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
        .navigationTitle("Preview")
        .navigationBarBackButtonHidden(true)
        .sheet(item: $shareItem) { item in
            ActivityShareSheet(items: [item.url])
        }
    }

    private var header: some View {
        Text("Pixel-perfect preview at LED resolution")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var previewArea: some View {
        Rectangle()
            .fill(Color.black)
            .aspectRatio(viewModel.resolution.aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                if viewModel.isProcessing || viewModel.isReprocessingDither {
                    ProgressView(viewModel.isReprocessingDither ? "Applying dither…" : "Processing…")
                        .tint(.white)
                        .foregroundStyle(.white)
                } else if !viewModel.frames.isEmpty {
                    let frame = viewModel.frames[viewModel.currentFrameIndex]
                    Image(uiImage: frame)
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(viewModel.resolution.aspectRatio, contentMode: .fit)
                }
            }
            .overlay(Picture3DBorder())
            .frame(maxHeight: 280)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
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
                    Task { await viewModel.saveGIF() }
                } label: {
                    if viewModel.isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                }
                .buttonStyle(GradientButtonStyle())
                .disabled(viewModel.isProcessing || viewModel.isReprocessingDither || viewModel.frames.isEmpty || viewModel.isSaving)
            }

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
