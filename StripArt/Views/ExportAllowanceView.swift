import SwiftUI

/// Shows whether the user still has free exports or already unlocked unlimited saves.
struct ExportAllowanceView: View {
    @ObservedObject var store: StoreManager
    let remaining: Int
    let limit: Int
    var compact: Bool = false

    var body: some View {
        if store.isUnlocked {
            unlockedBadge
        } else {
            FreeExportsStatusView(
                remaining: remaining,
                limit: limit,
                compact: compact
            )
        }
    }

    private var unlockedBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))

            Text("Unlimited exports unlocked")
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(BrandStyle.blue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, compact ? 8 : 10)
        .padding(.horizontal, 16)
        .background(BrandStyle.blue.opacity(0.12))
    }
}
