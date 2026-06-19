import CoreGraphics

enum ScrollDirection: String, CaseIterable, Identifiable {
    case left
    case right
    case up
    case down

    var id: String { rawValue }

    var label: String {
        switch self {
        case .left: "Links"
        case .right: "Rechts"
        case .up: "Boven"
        case .down: "Onder"
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

enum ScrollAxis {
    case horizontal
    case vertical
}
