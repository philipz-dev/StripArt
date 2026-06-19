import CoreGraphics
import CoreImage
import UIKit

enum DitherMode {
    case rgb
    case monochrome
}

struct ImageProcessor {

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Public API

    func generateScrollAnimation(
        from image: UIImage,
        cropRect: CGRect,
        resolution: LEDResolution,
        direction: ScrollDirection,
        ditherMode: DitherMode = .rgb,
        levelsPerChannel: Int = 8
    ) -> [CGImage] {
        guard resolution.isValid,
              let cgImage = image.cgImage,
              cropRect.width > 0,
              cropRect.height > 0 else {
            return []
        }

        let targetWidth = resolution.width
        let targetHeight = resolution.height

        let scaleX = CGFloat(targetWidth) / cropRect.width
        let scaleY = CGFloat(targetHeight) / cropRect.height
        let scale = min(scaleX, scaleY)

        guard let scaledSource = lanczosScale(cgImage, scale: scale) else {
            return []
        }

        let scaledCrop = CGRect(
            x: cropRect.origin.x * scale,
            y: cropRect.origin.y * scale,
            width: cropRect.width * scale,
            height: cropRect.height * scale
        ).integral

        let scrollRange = computeScrollRange(
            sourceSize: CGSize(width: scaledSource.width, height: scaledSource.height),
            viewport: scaledCrop,
            direction: direction
        )

        guard scrollRange.maxOffset >= scrollRange.minOffset else {
            if let frame = extractAndProcessFrame(
                from: scaledSource,
                viewport: scaledCrop,
                targetWidth: targetWidth,
                targetHeight: targetHeight,
                ditherMode: ditherMode,
                levelsPerChannel: levelsPerChannel
            ) {
                return [frame, frame]
            }
            return []
        }

        var offsets: [Int] = []
        for offset in scrollRange.minOffset...scrollRange.maxOffset {
            offsets.append(offset)
        }
        if scrollRange.maxOffset > scrollRange.minOffset {
            for offset in stride(from: scrollRange.maxOffset - 1, through: scrollRange.minOffset, by: -1) {
                offsets.append(offset)
            }
        }

        return offsets.compactMap { offset in
            let viewport = viewportRect(
                base: scaledCrop,
                offset: offset,
                direction: direction
            )
            return extractAndProcessFrame(
                from: scaledSource,
                viewport: viewport,
                targetWidth: targetWidth,
                targetHeight: targetHeight,
                ditherMode: ditherMode,
                levelsPerChannel: levelsPerChannel
            )
        }
    }

    // MARK: - Scaling

    func lanczosScale(_ image: CGImage, scale: CGFloat) -> CGImage? {
        guard scale > 0 else { return nil }

        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CILanczosScaleTransform") else {
            return bicubicScale(image, scale: scale)
        }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)

        guard let output = filter.outputImage,
              let result = ciContext.createCGImage(output, from: output.extent) else {
            return bicubicScale(image, scale: scale)
        }
        return result
    }

    func bicubicScale(_ image: CGImage, scale: CGFloat) -> CGImage? {
        let newWidth = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let newHeight = max(1, Int((CGFloat(image.height) * scale).rounded()))

        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }

    // MARK: - Dithering

    func floydSteinbergDither(
        _ image: CGImage,
        mode: DitherMode,
        levelsPerChannel: Int = 8
    ) -> CGImage? {
        let width = image.width
        let height = image.height

        guard var pixels = rgbaPixels(from: image) else { return nil }

        let levels = max(2, levelsPerChannel)
        let step = 255.0 / Double(levels - 1)

        func quantize(_ value: Double) -> Double {
            (value / step).rounded() * step
        }

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let old = pixels[index]

                let newR = quantize(Double(old.r))
                let newG = quantize(Double(old.g))
                let newB = quantize(Double(old.b))

                let final: RGBA
                switch mode {
                case .rgb:
                    final = RGBA(
                        r: UInt8(clamping: Int(newR.rounded())),
                        g: UInt8(clamping: Int(newG.rounded())),
                        b: UInt8(clamping: Int(newB.rounded())),
                        a: old.a
                    )
                case .monochrome:
                    let gray = 0.299 * newR + 0.587 * newG + 0.114 * newB
                    let qGray = quantize(gray)
                    final = RGBA(
                        r: UInt8(clamping: Int(qGray.rounded())),
                        g: UInt8(clamping: Int(qGray.rounded())),
                        b: UInt8(clamping: Int(qGray.rounded())),
                        a: old.a
                    )
                }

                pixels[index] = final

                let errR = Double(old.r) - Double(final.r)
                let errG = Double(old.g) - Double(final.g)
                let errB = Double(old.b) - Double(final.b)

                distributeError(
                    pixels: &pixels,
                    width: width,
                    height: height,
                    x: x,
                    y: y,
                    error: (errR, errG, errB)
                )
            }
        }

        return cgImage(from: pixels, width: width, height: height)
    }

    // MARK: - Private helpers

    private struct RGBA {
        var r, g, b, a: UInt8
    }

    private struct ScrollRange {
        let minOffset: Int
        let maxOffset: Int
    }

    private func computeScrollRange(
        sourceSize: CGSize,
        viewport: CGRect,
        direction: ScrollDirection
    ) -> ScrollRange {
        let maxOffset: Int
        switch direction {
        case .right:
            maxOffset = Int(floor(sourceSize.width - viewport.maxX))
        case .left:
            maxOffset = Int(floor(viewport.minX))
        case .down:
            maxOffset = Int(floor(sourceSize.height - viewport.maxY))
        case .up:
            maxOffset = Int(floor(viewport.minY))
        }
        return ScrollRange(minOffset: 0, maxOffset: max(0, maxOffset))
    }

    private func viewportRect(
        base: CGRect,
        offset: Int,
        direction: ScrollDirection
    ) -> CGRect {
        var rect = base
        switch direction {
        case .left:
            rect.origin.x -= CGFloat(offset)
        case .right:
            rect.origin.x += CGFloat(offset)
        case .up:
            rect.origin.y -= CGFloat(offset)
        case .down:
            rect.origin.y += CGFloat(offset)
        }
        return rect.integral
    }

    private func extractAndProcessFrame(
        from source: CGImage,
        viewport: CGRect,
        targetWidth: Int,
        targetHeight: Int,
        ditherMode: DitherMode,
        levelsPerChannel: Int
    ) -> CGImage? {
        guard let cropped = crop(source, to: viewport) else { return nil }
        guard let resized = resize(cropped, width: targetWidth, height: targetHeight) else { return nil }
        return floydSteinbergDither(resized, mode: ditherMode, levelsPerChannel: levelsPerChannel)
    }

    private func crop(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clamped = rect.intersection(bounds)
        guard clamped.width > 0, clamped.height > 0 else { return nil }
        return image.cropping(to: clamped)
    }

    private func resize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
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

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private func rgbaPixels(from image: CGImage) -> [RGBA]? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &data,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var pixels = [RGBA]()
        pixels.reserveCapacity(width * height)

        for i in stride(from: 0, to: data.count, by: 4) {
            pixels.append(RGBA(r: data[i], g: data[i + 1], b: data[i + 2], a: data[i + 3]))
        }
        return pixels
    }

    private func cgImage(from pixels: [RGBA], width: Int, height: Int) -> CGImage? {
        var data = [UInt8]()
        data.reserveCapacity(pixels.count * 4)
        for pixel in pixels {
            data.append(pixel.r)
            data.append(pixel.g)
            data.append(pixel.b)
            data.append(pixel.a)
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(data) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }
        return image
    }

    private func distributeError(
        pixels: inout [RGBA],
        width: Int,
        height: Int,
        x: Int,
        y: Int,
        error: (Double, Double, Double)
    ) {
        func addError(to px: Int, factor: Double) {
            guard px >= 0, px < pixels.count else { return }
            let r = Double(pixels[px].r) + error.0 * factor
            let g = Double(pixels[px].g) + error.1 * factor
            let b = Double(pixels[px].b) + error.2 * factor
            pixels[px].r = UInt8(clamping: Int(r.rounded()))
            pixels[px].g = UInt8(clamping: Int(g.rounded()))
            pixels[px].b = UInt8(clamping: Int(b.rounded()))
        }

        let coords: [(Int, Int, Double)] = [
            (x + 1, y, 7.0 / 16.0),
            (x - 1, y + 1, 3.0 / 16.0),
            (x, y + 1, 5.0 / 16.0),
            (x + 1, y + 1, 1.0 / 16.0)
        ]

        for (cx, cy, factor) in coords {
            guard cx >= 0, cx < width, cy >= 0, cy < height else { continue }
            addError(to: cy * width + cx, factor: factor)
        }
    }
}
