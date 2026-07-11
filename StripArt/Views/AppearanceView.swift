import SwiftUI

struct AppearanceView: View {
    @ObservedObject var viewModel: StripArtViewModel

    private enum AdjustmentMode: Hashable {
        case contrast
        case brightness
    }

    @State private var adjustmentMode: AdjustmentMode = .brightness

    /// Card padding chosen to equal the corner radius so the toggle row, which
    /// bleeds to the card's straight side edges, lines up with the dither buttons.
    private let cardPadding: CGFloat = 20

    var body: some View {
        VStack(spacing: 16) {
            ScreenTitle(title: "Appearance")

            StillPreviewArea(viewModel: viewModel)

            ditherSection

            adjustmentSection

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

    private var adjustmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Adjustments")
                .font(.headline)

            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    AdjustmentModeButton(
                        title: "Brightness",
                        isSelected: adjustmentMode == .brightness
                    ) {
                        adjustmentMode = .brightness
                    }
                    AdjustmentModeButton(
                        title: "Contrast",
                        isSelected: adjustmentMode == .contrast
                    ) {
                        adjustmentMode = .contrast
                    }
                }

                sliderContent
            }
            .cardStyle(padding: cardPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sliderContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Slider(value: activeBinding, in: 0...100, step: 1)
            HStack {
                Text(adjustmentMode == .contrast ? "Less" : "Darker")
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(activeDisplayValue)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Text(adjustmentMode == .contrast ? "More" : "Brighter")
                    .foregroundStyle(.primary)
            }
            .font(.caption)
        }
    }

    private var actionButtons: some View {
        DecisionButtons(
            cancel: { viewModel.cancelAppearance() },
            confirm: { viewModel.confirmAppearance() }
        )
    }

    private var activeDisplayValue: Int {
        switch adjustmentMode {
        case .contrast:
            Int(min(max((viewModel.contrast + 1) * 50, 0), 100))
        case .brightness:
            Int(min(max((viewModel.brightness + 1) * 50, 0), 100))
        }
    }

    private var activeBinding: Binding<Double> {
        Binding(
            get: { Double(activeDisplayValue) },
            set: { newValue in
                switch adjustmentMode {
                case .contrast:
                    viewModel.contrast = (newValue / 50) - 1
                case .brightness:
                    viewModel.brightness = (newValue / 50) - 1
                }
                viewModel.renderStillPreview()
            }
        )
    }
}

/// A contrast/brightness toggle, styled to match the dither algorithm buttons.
struct AdjustmentModeButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? .white : .primary)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? BrandStyle.blue : BrandStyle.neutral)
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [.white.opacity(0.28), .clear],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                        }
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
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
        .buttonStyle(.plain)
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
