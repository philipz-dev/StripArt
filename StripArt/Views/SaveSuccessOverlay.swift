import SwiftUI

struct SaveSuccessOverlay: View {
    let remainingFreeExports: Int
    let isUnlocked: Bool
    @ObservedObject var store: StoreManager
    let onConfirm: () -> Void

    private var showsFreemiumInfo: Bool { !isUnlocked }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                header

                VStack(spacing: 14) {
                    Text("Your animation has been saved to your Photo Library. You can import the GIF into your LED strip software.")
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryLabel))
                        .multilineTextAlignment(.center)
                        .lineSpacing(1)

                    if showsFreemiumInfo {
                        remainingBadge(for: remainingFreeExports)
                    } else {
                        unlockedBadge
                    }
                }

                VStack(spacing: 12) {
                    if showsFreemiumInfo {
                        unlockButton

                        if let error = store.purchaseError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    }

                    Button(action: onConfirm) {
                        Text("Done")
                    }
                    .buttonStyle(SuccessButtonStyle())
                }
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 12)
            .padding(28)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(BrandStyle.blue)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 80, height: 80)
                .background(
                    Circle()
                        .fill(Color(red: 0.36, green: 0.68, blue: 1.0).opacity(0.14))
                )

            Text("Saved to Photo Library")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Unlock

    private var unlockButton: some View {
        Button {
            store.purchaseError = nil
            Task { await store.purchase() }
        } label: {
            if store.purchaseInProgress {
                ProgressView()
                    .tint(BrandStyle.blue)
                    .frame(maxWidth: .infinity)
            } else {
                Label("Unlock unlimited · \(store.displayPrice)", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrandStyle.blue)
                    .frame(maxWidth: .infinity)
            }
        }
        .disabled(store.purchaseInProgress)
    }

    // MARK: - Remaining exports badge

    @ViewBuilder
    private func remainingBadge(for remaining: Int) -> some View {
        let isExhausted = remaining == 0
        let accent = isExhausted
            ? Color(red: 0.80, green: 0.18, blue: 0.18)
            : Color(red: 0.78, green: 0.45, blue: 0.05)
        Label {
            Text(remainingMessage(for: remaining))
                .font(.footnote.weight(.semibold))
        } icon: {
            Image(systemName: isExhausted ? "lock.fill" : "gift.fill")
                .font(.footnote)
        }
        .foregroundStyle(accent)
        .multilineTextAlignment(.center)
    }

    private func remainingMessage(for remaining: Int) -> String {
        if remaining == 0 {
            "That was your last free animation."
        } else if remaining == 1 {
            "1 free animation left."
        } else {
            "\(remaining) free animations left."
        }
    }

    private var unlockedBadge: some View {
        Label {
            Text("Unlimited exports unlocked")
                .font(.footnote.weight(.semibold))
        } icon: {
            Image(systemName: "checkmark.seal.fill")
                .font(.footnote)
        }
        .foregroundStyle(BrandStyle.blue)
        .multilineTextAlignment(.center)
    }
}

// MARK: - Done button

private struct SuccessButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemGreen))
            )
            .shadow(
                color: Color(.systemGreen).opacity(configuration.isPressed ? 0.10 : 0.20),
                radius: configuration.isPressed ? 2 : 4,
                x: 0,
                y: configuration.isPressed ? 1 : 2
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
