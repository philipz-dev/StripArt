import SwiftUI

/// Shows whether the user still has free exports or already unlocked unlimited saves.
struct ExportAllowanceView: View {
    @ObservedObject var store: StoreManager
    let remaining: Int
    let limit: Int
    var compact: Bool = false
    var showsUnlockButton: Bool = false

    @ViewBuilder
    var body: some View {
        if !store.isUnlocked {
            VStack(spacing: 12) {
                FreeExportsStatusView(
                    remaining: remaining,
                    limit: limit,
                    compact: compact
                )

                if showsUnlockButton {
                    unlockButton

                    if let error = store.purchaseError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color(red: 0.75, green: 0.12, blue: 0.12))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var unlockButton: some View {
        Button {
            store.purchaseError = nil
            Task { await store.purchase() }
        } label: {
            if store.purchaseInProgress {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
            } else {
                Label("Unlock unlimited · \(store.displayPrice)", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(GradientButtonStyle())
        .disabled(store.purchaseInProgress)
    }
}
