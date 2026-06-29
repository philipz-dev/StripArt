import SwiftUI
import UIKit

/// One LED's resolved color and how brightly it glows. Off LEDs are skipped so
/// the black backing shows through, mimicking a physical strip.
struct LEDCell: Sendable {
    let color: Color
    let brightness: Double
    let isOn: Bool
}

/// A frame decoded into a grid of LED cells at the exact LED resolution. The
/// grid is precomputed once per frame so drawing stays cheap during animation.
struct LEDPixelGrid: Sendable {
    let columns: Int
    let rows: Int
    let cells: [LEDCell]

    /// Reads the pixels of `image` (assumed to already be at LED resolution) into
    /// an LED grid. `columns`/`rows` default to the image's own dimensions.
    init(image: CGImage, columns: Int? = nil, rows: Int? = nil) {
        let w = max(1, columns ?? image.width)
        let h = max(1, rows ?? image.height)
        self.columns = w
        self.rows = h

        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        buffer.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: w,
                    height: h,
                    bitsPerComponent: 8,
                    bytesPerRow: w * 4,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                  ) else { return }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }

        var result = [LEDCell]()
        result.reserveCapacity(w * h)
        for i in 0..<(w * h) {
            let r = Double(buffer[i * 4]) / 255.0
            let g = Double(buffer[i * 4 + 1]) / 255.0
            let b = Double(buffer[i * 4 + 2]) / 255.0
            // Perceived brightness; also decides whether the LED is lit.
            let brightness = 0.299 * r + 0.587 * g + 0.114 * b
            let isOn = max(r, max(g, b)) > 0.05
            result.append(LEDCell(color: Color(red: r, green: g, blue: b), brightness: brightness, isOn: isOn))
        }
        self.cells = result
    }

    /// Empty (all-off) grid used as a safe fallback.
    init() {
        columns = 0
        rows = 0
        cells = []
    }
}

/// Draws an LED grid as round, glowing LEDs separated by black gaps — a visual
/// approximation of a real LED bar. Purely cosmetic; the exported GIF stays a
/// flat pixel grid.
struct LEDBarCanvas: View {
    let grid: LEDPixelGrid

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

            let columns = grid.columns
            let rows = grid.rows
            guard columns > 0, rows > 0, grid.cells.count == columns * rows else { return }

            let cellW = size.width / CGFloat(columns)
            let cellH = size.height / CGFloat(rows)
            let radius = min(cellW, cellH) * 0.5 * 0.86

            for y in 0..<rows {
                for x in 0..<columns {
                    let cell = grid.cells[y * columns + x]
                    guard cell.isOn else { continue }

                    let cx = (CGFloat(x) + 0.5) * cellW
                    let cy = (CGFloat(y) + 0.5) * cellH

                    // Soft glow around brighter LEDs.
                    if cell.brightness > 0.15 {
                        let glowR = radius * 1.35
                        let glowRect = CGRect(x: cx - glowR, y: cy - glowR, width: glowR * 2, height: glowR * 2)
                        context.fill(Path(ellipseIn: glowRect), with: .color(cell.color.opacity(0.18)))
                    }

                    let dotRect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: dotRect), with: .color(cell.color))

                    // Small specular highlight for a rounded, 3D LED feel.
                    if cell.brightness > 0.22 {
                        let hr = radius * 0.42
                        let hx = cx - radius * 0.3
                        let hy = cy - radius * 0.3
                        let hRect = CGRect(x: hx - hr, y: hy - hr, width: hr * 2, height: hr * 2)
                        context.fill(Path(ellipseIn: hRect), with: .color(.white.opacity(0.22)))
                    }
                }
            }
        }
    }
}

/// Convenience wrapper that builds the grid from a single frame and renders it.
/// The grid is derived from the image (already at LED resolution).
struct LEDBarView: View {
    let image: CGImage

    var body: some View {
        LEDBarCanvas(grid: LEDPixelGrid(image: image))
    }
}
