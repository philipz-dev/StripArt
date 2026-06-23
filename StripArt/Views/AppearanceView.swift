import SwiftUI

struct AppearanceView: View {
    @ObservedObject var viewModel: StripArtViewModel

    var body: some View {
        VStack(spacing: 16) {
            ScreenTitle(title: "Appearance")

            StillPreviewArea(viewModel: viewModel)

            ditherSection

            contrastSection

            actionButtons
        }
        .padding(24)
        .navigationBarHidden(true)
    }

    private var ditherSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dithering algorithm")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(DitherAlgorithm.allCases) { algorithm in
                    DitherChoiceButton(
                        algorithm: algorithm,
                        isSelected: viewModel.ditherAlgorithm == algorithm
                    ) {
                        viewModel.selectDitherAlgorithm(algorithm)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var contrastSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Contrast")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Slider(value: contrastBinding, in: -1...1, step: 0.05)
                HStack {
                    Text("Less")
                    Spacer()
                    Text("More")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .cardStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionButtons: some View {
        DecisionButtons(
            cancel: { viewModel.cancelAppearance() },
            confirm: { viewModel.confirmAppearance() }
        )
    }

    private var contrastBinding: Binding<Double> {
        Binding(
            get: { viewModel.contrast },
            set: { newValue in
                viewModel.contrast = newValue
                viewModel.renderStillPreview()
            }
        )
    }
}

/// The whole dithered strip shown as a single still image, scaled to fit on
/// screen (no scrolling, no motion).
struct StillPreviewArea: View {
    @ObservedObject var viewModel: StripArtViewModel

    private var stripAspectRatio: CGFloat {
        guard let still = viewModel.stillPreview, still.size.height > 0 else {
            return viewModel.resolution.aspectRatio
        }
        return still.size.width / still.size.height
    }

    var body: some View {
        ZStack {
            if let still = viewModel.stillPreview {
                Image(uiImage: still)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(stripAspectRatio, contentMode: .fit)
                    .overlay(Picture3DBorder())
            }

            if viewModel.isRenderingStill && viewModel.stillPreview == nil {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One of the three dither algorithm choices, styled as a glossy 3D toggle.
struct DitherChoiceButton: View {
    let algorithm: DitherAlgorithm
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(algorithm.label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(isSelected ? .white : .primary)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? BrandStyle.blue : BrandStyle.neutral)
                        if isSelected {
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
                                isSelected ? .white.opacity(0.25) : .black.opacity(0.08),
                                lineWidth: 1
                            )
                    }
                )
                .shadow(
                    color: (isSelected ? BrandStyle.blueShadow : .black).opacity(isSelected ? 0.35 : 0.12),
                    radius: isSelected ? 8 : 4,
                    x: 0,
                    y: isSelected ? 4 : 2
                )
        }
        .buttonStyle(.plain)
    }
}
