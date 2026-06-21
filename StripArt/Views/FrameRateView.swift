import SwiftUI

struct FrameRateView: View {
    @ObservedObject var viewModel: StripArtViewModel

    var body: some View {
        VStack(spacing: 24) {
            header

            if viewModel.isPreparingFrames {
                Spacer()
                ProgressView("Preparing frames…")
                Spacer()
            } else {
                frameControl
                Spacer()
                actionButtons
            }
        }
        .padding(24)
        .navigationBarHidden(true)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Frame Rate")
                .font(.title2.bold())
            Text("The maximum is a full bounce with 1-pixel steps. Lower it for fewer, larger steps.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var frameControl: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Frames")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.frameCount) / \(viewModel.maxFrameCount)")
                    .font(.system(.title3, design: .rounded).monospacedDigit())
                    .foregroundStyle(.tint)
            }

            if isAdjustable {
                Slider(
                    value: frameCountBinding,
                    in: Double(viewModel.minFrameCount)...Double(viewModel.maxFrameCount),
                    step: 1
                )

                HStack {
                    Text("Min \(viewModel.minFrameCount)")
                    Spacer()
                    Text("Max \(viewModel.maxFrameCount)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Stepper(
                    "Adjust frames",
                    value: $viewModel.frameCount,
                    in: viewModel.minFrameCount...viewModel.maxFrameCount
                )
                .labelsHidden()
            } else {
                Text("This animation only has \(viewModel.maxFrameCount) frames, so it can't be reduced further.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var actionButtons: some View {
        DecisionButtons(
            confirmEnabled: viewModel.maxFrameCount != 0,
            cancel: { viewModel.cancelFrameRate() },
            confirm: { viewModel.confirmFrameRate() }
        )
    }

    private var isAdjustable: Bool {
        viewModel.maxFrameCount > viewModel.minFrameCount
    }

    private var frameCountBinding: Binding<Double> {
        Binding(
            get: { Double(viewModel.frameCount) },
            set: { viewModel.frameCount = Int($0.rounded()) }
        )
    }
}
