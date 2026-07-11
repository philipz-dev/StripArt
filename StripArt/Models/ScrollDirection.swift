import CoreGraphics

enum ScrollDirection: String, CaseIterable, Identifiable {
    case left
    case right
    case up
    case down

    var id: String { rawValue }

    var label: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .up: "Up"
        case .down: "Down"
        }
    }

    var systemImageName: String {
        switch self {
        case .left: "arrow.left"
        case .right: "arrow.right"
        case .up: "arrow.up"
        case .down: "arrow.down"
        }
    }

    var scrollAxis: ScrollAxis {
        switch self {
        case .left, .right: .horizontal
        case .up, .down: .vertical
        }
    }

    var step: CGPoint {
        switch self {
        case .left: CGPoint(x: -1, y: 0)
        case .right: CGPoint(x: 1, y: 0)
        case .up: CGPoint(x: 0, y: -1)
        case .down: CGPoint(x: 0, y: 1)
        }
    }
}

enum ScrollAxis: String, CaseIterable, Identifiable {
    case horizontal
    case vertical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .horizontal: "Horizontal"
        case .vertical: "Vertical"
        }
    }

    /// A double-headed arrow representing movement along the axis.
    var systemImageName: String {
        switch self {
        case .horizontal: "arrow.left.arrow.right"
        case .vertical: "arrow.up.arrow.down"
        }
    }

    /// Default travel direction chosen when the user picks this axis.
    var defaultDirection: ScrollDirection {
        switch self {
        case .horizontal: .right
        case .vertical: .down
        }
    }
}
