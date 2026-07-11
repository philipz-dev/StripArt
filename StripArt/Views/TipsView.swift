import SwiftUI

struct TipsView: View {
    let isUnlocked: Bool
    let remaining: Int
    let limit: Int
    @Binding var doNotShowAgain: Bool
    let onContinue: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 28) {
                header

                exportStatusBadge

                VStack(alignment: .leading, spacing: 22) {
                    tipRow(
                        icon: "aspectratio",
                        title: "Set your LED bar resolution",
                        detail: "Resolution can be found on the LED bar itself or in the manual."
                    )
                    tipRow(
                        icon: "sparkles",
                        title: "Simple beats detailed",
                        detail: "On a small LED bar, a single face or simple logo shows up better than a crowded group photo."
                    )
                    tipRow(
                        icon: "square.stack.3d.up.fill",
                        title: "~100 frames is a sweet spot",
                        detail: "Smooth enough to scroll, small enough for most LED apps and device memory."
                    )
                }

                bottomControls
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
            .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 12)
            .padding(28)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            Image(systemName: "lightbulb.max.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.12))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 76, height: 76)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .fill(Color(red: 1.0, green: 0.72, blue: 0.12).opacity(0.12))
                        )
                )
                .overlay(
                    Circle().strokeBorder(Color(.separator).opacity(0.3), lineWidth: 1)
                )

            Text("Tips")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Export status

    private var exportStatusBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: exportStatusIcon)
                .font(.subheadline.weight(.semibold))

            Text(exportStatusText)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(exportStatusColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(exportStatusColor.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(exportStatusColor.opacity(0.28), lineWidth: 1)
        )
    }

    private var exportStatusIcon: String {
        if isUnlocked { "checkmark.seal.fill" }
        else if remaining == 0 { "lock.fill" }
        else { "gift.fill" }
    }

    private var exportStatusColor: Color {
        if isUnlocked {
            Color(red: 0.05, green: 0.27, blue: 0.78)
        } else if remaining == 0 {
            Color(red: 0.68, green: 0.08, blue: 0.10)
        } else {
            Color(red: 0.82, green: 0.18, blue: 0.18)
        }
    }

    private var exportStatusText: String {
        if isUnlocked {
            "Unlimited exports"
        } else if remaining == 0 {
            "No free animations remaining"
        } else if remaining == 1 {
            "1 of \(limit) free animations remaining"
        } else {
            "\(remaining) of \(limit) free animations remaining"
        }
    }

    // MARK: - Tip row

    private func tipRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(BrandStyle.blue)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        VStack(spacing: 18) {
            Toggle(isOn: $doNotShowAgain) {
                Text("Do not show tips again")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )

            Button(action: onContinue) {
                Text("Got it!")
            }
            .buttonStyle(
                GradientButtonStyle(
                    gradient: BrandStyle.green,
                    shadowColor: BrandStyle.greenShadow
                )
            )
        }
    }
}
