import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import UIKit

/// Re-renders a saved animation GIF as the glowing "LED bar" simulation seen on
/// the preview screen: round, glowing LEDs separated by black gaps, with no
/// surrounding frame. The drawing here mirrors `LEDBarCanvas` so the exported
/// file matches what the user sees in the app.
enum LEDSimulationRenderer {

    /// Builds an animated GIF of the LED simulation from `gifData`.
    ///
    /// - Parameters:
    ///   - gifData: The flat, pixel-grid GIF stored in the gallery.
    ///   - maxLongSide: Upper bound for the longest output dimension, keeping the
    ///     exported file a reasonable size.
    /// - Returns: GIF data, or `nil` if decoding/encoding fails.
    static func makeSimulationGIF(from gifData: Data, maxLongSide: Int = 900) -> Data? {
        guard let source = CGImageSourceCreateWithData(gifData as CFData, nil) else { return nil }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0,
              let firstFrame = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let columns = max(1, firstFrame.width)
        let rows = max(1, firstFrame.height)
        let longSide = max(columns, rows)
        // One LED occupies `cell` × `cell` points; clamp so small grids still get
        // crisp round dots and large grids stay within `maxLongSide`.
        let cell = max(8, min(22, maxLongSide / longSide))
        let outputWidth = columns * cell
        let outputHeight = rows * cell

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ) else {
            return nil
        }

        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        var renderedAny = false
        for index in 0..<frameCount {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            autoreleasepool {
                guard let frame = renderFrame(
                    from: image,
                    columns: columns,
                    rows: rows,
                    cell: cell,
                    width: outputWidth,
                    height: outputHeight
                ) else { return }

                let delay = frameDelay(source: source, index: index)
                let frameProperties: [String: Any] = [
                    kCGImagePropertyGIFDictionary as String: [
                        kCGImagePropertyGIFDelayTime as String: delay,
                        kCGImagePropertyGIFUnclampedDelayTime as String: delay
                    ]
                ]
                CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
                renderedAny = true
            }
        }

        guard renderedAny, CGImageDestinationFinalize(destination) else { return nil }
        return outputData as Data
    }

    // MARK: - Frame drawing

    private static func renderFrame(
        from image: CGImage,
        columns: Int,
        rows: Int,
        cell: Int,
        width: Int,
        height: Int
    ) -> CGImage? {
        // Read the source frame's pixels at LED resolution.
        var pixels = [UInt8](repeating: 0, count: columns * rows * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let readInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let didRead: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: columns,
                    height: rows,
                    bitsPerComponent: 8,
                    bytesPerRow: columns * 4,
                    space: colorSpace,
                    bitmapInfo: readInfo
                  ) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
            return true
        }
        guard didRead else { return nil }

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // Black backing, like the real strip / preview.
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let cellF = CGFloat(cell)
        let radius = cellF * 0.5 * 0.86

        for y in 0..<rows {
            for x in 0..<columns {
                let i = (y * columns + x) * 4
                let r = Double(pixels[i]) / 255.0
                let g = Double(pixels[i + 1]) / 255.0
                let b = Double(pixels[i + 2]) / 255.0

                // Off LEDs let the black backing show through.
                guard max(r, max(g, b)) > 0.05 else { continue }
                let brightness = 0.299 * r + 0.587 * g + 0.114 * b

                let cx = (CGFloat(x) + 0.5) * cellF
                // CGContext origin is bottom-left; source row 0 is the top scanline.
                let cy = CGFloat(height) - (CGFloat(y) + 0.5) * cellF

                // Soft glow around brighter LEDs.
                if brightness > 0.15 {
                    let glowR = radius * 1.35
                    ctx.setFillColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 0.18)
                    ctx.fillEllipse(in: CGRect(x: cx - glowR, y: cy - glowR, width: glowR * 2, height: glowR * 2))
                }

                ctx.setFillColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
                ctx.fillEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))

                // Specular highlight toward the top-left (light from top-left).
                if brightness > 0.22 {
                    let hr = radius * 0.42
                    let hx = cx - radius * 0.3
                    let hy = cy + radius * 0.3
                    ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.22)
                    ctx.fillEllipse(in: CGRect(x: hx - hr, y: hy - hr, width: hr * 2, height: hr * 2))
                }
            }
        }

        return ctx.makeImage()
    }

    // MARK: - Timing

    private static func frameDelay(source: CGImageSource, index: Int) -> Double {
        let fallback = 0.08
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return fallback
        }
        if let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclamped > 0 {
            return unclamped
        }
        if let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double, clamped > 0 {
            return clamped
        }
        return fallback
    }
}
