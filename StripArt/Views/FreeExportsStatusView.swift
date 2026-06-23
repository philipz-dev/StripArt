import SwiftUI

struct FreeExportsStatusView: View {
    let remaining: Int
    let limit: Int
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: remaining == 0 ? "lock.fill" : "gift.fill")
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))

            Text(statusText)
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(remaining == 0 ? Color.red : Color.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, compact ? 8 : 10)
        .padding(.horizontal, 16)
        .background(
            (remaining == 0 ? Color.red : Color.orange).opacity(0.12)
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
