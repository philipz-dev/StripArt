import SwiftUI

struct TipsView: View {
    @Binding var doNotShowAgain: Bool
    let onContinue: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 20) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(BrandStyle.blue)
                    .symbolRenderingMode(.hierarchical)

                Text("Tips")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 14) {
                    tipRow(
                        title: "Make sure to set your LED bar resolution correctly",
                        detail: "Resolution can be found on the LED bar itself or in the manual."
                    )
                    tipRow(
                        title: "Simple beats detailed",
                        detail: "On a small LED bar, a single face or simple logo shows up better than a crowded group photo."
                    )
                    tipRow(
                        title: "~100 frames is a sweet spot",
                        detail: "Smooth enough to scroll, small enough for most LED apps and device memory."
                    )
                }

                Toggle(isOn: $doNotShowAgain) {
                    Text("Do not show tips again")
                        .font(.subheadline)
                        .foregroundStyle(Color(red: 0.28, green: 0.32, blue: 0.38))
                }
                .toggleStyle(.switch)
                .tint(Color(red: 0.05, green: 0.27, blue: 0.78))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

                Button(action: onContinue) {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(
                    CircleIconButtonStyle(
                        gradient: BrandStyle.green,
                        shadowColor: BrandStyle.greenShadow,
                        diameter: 72,
                        iconSize: 28
                    )
                )
                .padding(.top, 4)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.8), lineWidth: 1)
            )
            .padding(32)
        }
    }

    private func tipRow(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("•")
                .font(.body.bold())
                .foregroundStyle(BrandStyle.blue)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Color(red: 0.28, green: 0.32, blue: 0.38))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
