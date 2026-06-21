import SwiftUI

struct PaywallView: View {
    @ObservedObject var store: StoreManager
    let freeLimit: Int
    let onClose: () -> Void
    let onUnlocked: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44))
                    .foregroundStyle(BrandStyle.blue)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 10) {
                    Text("Unlock unlimited exports")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    Text("You've used your \(freeLimit) free animations. Unlock StripArt once to save as many as you like.")
                        .font(.subheadline)
                        .foregroundStyle(Color(red: 0.28, green: 0.32, blue: 0.38))
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await purchase() }
                } label: {
                    if store.purchaseInProgress {
                        ProgressView().tint(.white)
                    } else {
                        Text("Unlock for \(store.displayPrice)")
                    }
                }
                .buttonStyle(GradientButtonStyle())
                .disabled(store.purchaseInProgress)

                Button {
                    Task { await restore() }
                } label: {
                    Text("Restore Purchase")
                }
                .buttonStyle(
                    GradientButtonStyle(
                        gradient: BrandStyle.neutral,
                        shadowColor: .black,
                        foreground: .primary
                    )
                )
                .disabled(store.purchaseInProgress)

                if let error = store.purchaseError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button(action: onClose) {
                    Text("Maybe later")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
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
        .onChange(of: store.isUnlocked) { _, unlocked in
            if unlocked { onUnlocked() }
        }
    }

    private func purchase() async {
        store.purchaseError = nil
        await store.purchase()
    }

    private func restore() async {
        store.purchaseError = nil
        await store.restore()
    }
}
