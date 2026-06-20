import SwiftUI

struct PreviewView: View {
    @ObservedObject var viewModel: StripArtViewModel
    @State private var shareItem: ShareGIFItem?

    var body: some View {
        VStack(spacing: 24) {
            header

            previewArea

            ditherPicker

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
        VStack(spacing: 6) {
            Text("Dithered Animation")
                .font(.title2.bold())
            Text("Pixel-perfect preview at LED resolution")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        ZStack {
            Rectangle()
                .fill(Color.black)
                .aspectRatio(viewModel.resolution.aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay(
                    Rectangle()
                        .stroke(.secondary.opacity(0.35), lineWidth: 1)
                )

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
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxHeight: 280)
    }

    private var ditherPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dithering algorithm")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(DitherAlgorithm.allCases) { algorithm in
                    let selected = viewModel.ditherAlgorithm == algorithm
                    Button {
                        viewModel.selectDitherAlgorithm(algorithm)
                    } label: {
                        Text(algorithm.label)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .foregroundStyle(selected ? .white : .primary)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(selected ? BrandStyle.blue : BrandStyle.neutral)
                                    if selected {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(
                                                LinearGradient(
                                                    colors: [.white.opacity(0.28), .clear],
                                                    startPoint: .top,
                                                    endPoint: .center
                                                )
                                            )
                                    }
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(
                                            selected ? .white.opacity(0.25) : .black.opacity(0.08),
                                            lineWidth: 1
                                        )
                                }
                            )
                            .shadow(
                                color: (selected ? BrandStyle.blueShadow : .black).opacity(selected ? 0.35 : 0.12),
                                radius: selected ? 8 : 4,
                                x: 0,
                                y: selected ? 4 : 2
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isReprocessingDither || viewModel.isProcessing)
                }
            }
        }
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
