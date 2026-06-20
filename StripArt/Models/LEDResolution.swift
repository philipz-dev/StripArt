import Foundation

struct LEDResolution: Equatable, Hashable {
    var height: Int
    var width: Int

    static let `default` = LEDResolution(height: 16, width: 96)

    var aspectRatio: CGFloat {
        guard height > 0 else { return 1 }
        return CGFloat(width) / CGFloat(height)
    }

    /// Width:height reduced to the smallest possible whole numbers (e.g. 96×16 → 6:1).
    var simplifiedAspectRatioLabel: String {
        let divisor = Self.gcd(width, height)
        guard divisor > 0 else { return "\(width):\(height)" }
        return "\(width / divisor):\(height / divisor)"
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = abs(a)
        var y = abs(b)
        while y != 0 {
            (x, y) = (y, x % y)
        }
        return x
    }

    var isValid: Bool {
        height >= 1 && width >= 1 && height <= 256 && width <= 512
    }

    var pixelCount: Int {
        height * width
    }

    // MARK: - Persistence

    private enum Storage {
        static let heightKey = "savedLEDHeight"
        static let widthKey = "savedLEDWidth"
    }

    static func loadSaved() -> LEDResolution? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Storage.heightKey) != nil else { return nil }
        let resolution = LEDResolution(
            height: defaults.integer(forKey: Storage.heightKey),
            width: defaults.integer(forKey: Storage.widthKey)
        )
        return resolution.isValid ? resolution : nil
    }

    func save() {
        guard isValid else { return }
        let defaults = UserDefaults.standard
        defaults.set(height, forKey: Storage.heightKey)
        defaults.set(width, forKey: Storage.widthKey)
    }
}
