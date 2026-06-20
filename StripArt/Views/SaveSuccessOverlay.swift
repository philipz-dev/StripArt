import SwiftUI

struct SaveSuccessOverlay: View {
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 44))
                    .foregroundStyle(BrandStyle.blue)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 10) {
                    Text("Saved to Photo Library")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)

                    Text("Your animation has been saved to your Photo Library. You can import the GIF into your LED strip software.")
                        .font(.subheadline)
                        .foregroundStyle(Color(red: 0.28, green: 0.32, blue: 0.38))
                        .multilineTextAlignment(.center)
                }

                Button(action: onConfirm) {
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
}
