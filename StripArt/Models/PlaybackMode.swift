import Foundation

/// How the scroll animation repeats.
enum PlaybackMode: String, CaseIterable, Identifiable, Sendable {
    /// Start → end, then back to start (frames play forward and reversed).
    case bounce
    /// Start → end, then jump straight back to the start (forward only).
    case loop

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bounce: "Bounce"
        case .loop: "Loop"
        }
    }

    var subtitle: String {
        switch self {
        case .bounce: "Scrolls to the end, then back"
        case .loop: "Scrolls to the end, then restarts"
        }
    }

    var systemImageName: String {
        switch self {
        case .bounce: "arrow.left.arrow.right"
        case .loop: "repeat"
        }
    }
}
