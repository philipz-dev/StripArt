import Foundation

struct LEDResolution: Equatable, Hashable {
    var height: Int
    var width: Int

    static let `default` = LEDResolution(height: 16, width: 96)

    var aspectRatio: CGFloat {
        guard height > 0 else { return 1 }
        return CGFloat(width) / CGFloat(height)
    }

    var isValid: Bool {
        height >= 1 && width >= 1 && height <= 256 && width <= 512
    }

    var pixelCount: Int {
        height * width
    }
}
