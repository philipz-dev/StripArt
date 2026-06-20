import Foundation

enum DitherAlgorithm: String, CaseIterable, Identifiable, Sendable {
    case floydSteinberg
    case atkinson
    case ordered

    var id: String { rawValue }

    var label: String {
        switch self {
        case .floydSteinberg: "Floyd–Steinberg"
        case .atkinson: "Atkinson"
        case .ordered: "Ordered"
        }
    }
}
