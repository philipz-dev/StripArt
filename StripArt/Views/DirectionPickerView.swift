import SwiftUI

struct DirectionPickerView: View {
    @ObservedObject var viewModel: StripArtViewModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Scroll Direction")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text("Choose the direction the image scrolls through the LED window.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                directionPad

                Button("Cancel") {
                    viewModel.cancelDirection()
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.top, 8)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding(24)
        }
    }

    private var directionPad: some View {
        VStack(spacing: 16) {
            directionButton(.up)

            HStack(spacing: 16) {
                directionButton(.left)
                directionButton(.right)
            }

            directionButton(.down)
        }
    }

    private func directionButton(_ direction: ScrollDirection) -> some View {
        Button {
            viewModel.selectDirection(direction)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: direction.systemImageName)
                    .font(.title.bold())
                Text(direction.label)
                    .font(.caption)
            }
            .foregroundStyle(.white)
            .frame(width: 88, height: 88)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
