import SwiftUI

struct FreeExportsStatusView: View {
    let remaining: Int
    let limit: Int
    var compact: Bool = false

    private var isExhausted: Bool { remaining == 0 }

    private var accentColor: Color {
        isExhausted
            ? Color(red: 0.68, green: 0.08, blue: 0.10)
            : Color(red: 0.82, green: 0.18, blue: 0.18)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isExhausted ? "lock.fill" : "gift.fill")
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))

            Text(statusText)
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(accentColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, compact ? 8 : 10)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accentColor.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accentColor.opacity(0.28), lineWidth: 1)
        )
    }

    private var statusText: String {
        if remaining == 0 {
            "No free animations left — unlock for unlimited exports"
        } else if remaining == 1 {
            "1 free animation left"
        } else {
            "\(remaining) of \(limit) free animations left"
        }
    }
}
