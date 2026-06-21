import CoreGraphics
import UIKit

enum DitherMode {
    case rgb
    case monochrome
}

/// Undithered scroll strip plus metadata needed to re-render with another algorithm.
struct ScrollAnimationSource: Sendable {
    let unditheredPixels: [UInt8]
    let sourceWidth: Int
    let sourceHeight: Int
    let targetWidth: Int
    let targetHeight: Int
    let baseViewport: CGRect
    let offsets: [Int]
    let direction: ScrollDirection
}

struct ImageProcessor {

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    /// Explicit RGBA byte order — avoids misreading UIKit's default BGRA buffers.
    private static let rgbaBitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
        | CGImageAlphaInfo.noneSkipLast.rawValue

    private static let bayer4x4: [[Int]] = [
        [0, 8, 2, 10],
        [12, 4, 14, 6],
        [3, 11, 1, 9],
        [15, 7, 13, 5]
    ]

    // MARK: - Public API

    func generateScrollAnimation(
        from image: UIImage,
        cropRect: CGRect,
        resolution: LEDResolution,
        direction: ScrollDirection,
        algorithm: DitherAlgorithm = .ordered,
        ditherMode: DitherMode = .rgb,
        levelsPerChannel: Int = 8
    ) -> [CGImage] {
        guard let source = prepareScrollAnimationSource(
            from: image,
            cropRect: cropRect,
            resolution: resolution,
            direction: direction
        ) else {
            return []
        }

        return renderScrollAnimation(
            from: source,
            algorithm: algorithm,
            mode: ditherMode,
            levelsPerChannel: levelsPerChannel
        )
    }

    func prepareScrollAnimationSource(
        from image: UIImage,
        cropRect: CGRect,
        endCropRect: CGRect? = nil,
        resolution: LEDResolution,
        direction: ScrollDirection
    ) -> ScrollAnimationSource? {
        guard resolution.isValid,
              let cgImage = image.cgImage,
              cropRect.width > 0,
              cropRect.height > 0 else {
            return nil
        }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let pointSize = CGSize(width: image.size.width, height: image.size.height)

        let adjustedCrop = cropRect.scaled(from: pointSize, to: imageSize)
        // A zero end rect means "no explicit end position".
        let adjustedEnd: CGRect? = {
            guard let endCropRect, endCropRect.width > 0, endCropRect.height > 0 else { return nil }
            return endCropRect.scaled(from: pointSize, to: imageSize)
        }()

        let targetWidth = resolution.width
        let targetHeight = resolution.height

        var workingImage = cgImage
        var workingCrop = adjustedCrop
        var workingEnd = adjustedEnd
        var workingImageSize = imageSize

        var sourceStrip = sourceStripRect(
            crop: workingCrop,
            imageSize: workingImageSize,
            direction: direction
        )

        var stripScale: CGFloat
        var workingWidth: Int
        var workingHeight: Int

        switch direction.scrollAxis {
        case .horizontal:
            stripScale = CGFloat(targetHeight) / sourceStrip.height
            workingWidth = max(1, Int((sourceStrip.width * stripScale).rounded()))
            workingHeight = targetHeight
        case .vertical:
            stripScale = CGFloat(targetWidth) / sourceStrip.width
            workingWidth = targetWidth
            workingHeight = max(1, Int((sourceStrip.height * stripScale).rounded()))
        }

        let oversample: CGFloat = 2
        let preScale = min(
            1,
            (CGFloat(workingWidth) * oversample) / sourceStrip.width,
            (CGFloat(workingHeight) * oversample) / sourceStrip.height
        )

        if preScale < 0.999 {
            let newWidth = max(1, Int((CGFloat(cgImage.width) * preScale).rounded()))
            let newHeight = max(1, Int((CGFloat(cgImage.height) * preScale).rounded()))

            if let downsampled = bicubicScaleToSize(cgImage, width: newWidth, height: newHeight) {
                workingImage = downsampled
                workingImageSize = CGSize(width: newWidth, height: newHeight)
                workingCrop = CGRect(
                    x: adjustedCrop.minX * preScale,
                    y: adjustedCrop.minY * preScale,
                    width: adjustedCrop.width * preScale,
                    height: adjustedCrop.height * preScale
                )
                workingEnd = adjustedEnd.map { rect in
                    CGRect(
                        x: rect.minX * preScale,
                        y: rect.minY * preScale,
                        width: rect.width * preScale,
                        height: rect.height * preScale
                    )
                }
                sourceStrip = sourceStripRect(
                    crop: workingCrop,
                    imageSize: workingImageSize,
                    direction: direction
                )

                switch direction.scrollAxis {
                case .horizontal:
                    stripScale = CGFloat(targetHeight) / sourceStrip.height
                    workingWidth = max(1, Int((sourceStrip.width * stripScale).rounded()))
                    workingHeight = targetHeight
                case .vertical:
                    stripScale = CGFloat(targetWidth) / sourceStrip.width
                    workingWidth = targetWidth
                    workingHeight = max(1, Int((sourceStrip.height * stripScale).rounded()))
                }
            }
        }

        guard let scaledSource = cropAndScaleToSize(
            workingImage,
            sourceRect: sourceStrip,
            width: workingWidth,
            height: workingHeight
        ),
              let unditheredPixels = copyPixelData(from: scaledSource) else {
            return nil
        }

        let sourceSize = CGSize(width: workingWidth, height: workingHeight)
        let scaledCrop = scaledCropRect(
            crop: workingCrop,
            sourceStrip: sourceStrip,
            stripScale: stripScale,
            targetWidth: targetWidth,
            targetHeight: targetHeight
        )

        let scrollRange = computeScrollRange(
            sourceSize: sourceSize,
            viewport: scaledCrop,
            direction: direction
        )

        let minOffset = scrollRange.minOffset
        var maxOffset = scrollRange.maxOffset

        // Limit scrolling to the user-defined end position when provided.
        if let workingEnd {
            let scaledEnd = scaledCropRect(
                crop: workingEnd,
                sourceStrip: sourceStrip,
                stripScale: stripScale,
                targetWidth: targetWidth,
                targetHeight: targetHeight
            )
            let endOffset: CGFloat
            switch direction.scrollAxis {
            case .horizontal:
                endOffset = abs(scaledEnd.minX - scaledCrop.minX)
            case .vertical:
                endOffset = abs(scaledEnd.minY - scaledCrop.minY)
            }
            maxOffset = min(maxOffset, max(0, Int(endOffset.rounded())))
        }

        let offsets: [Int]
        if maxOffset > minOffset {
            var values: [Int] = []
            values.reserveCapacity((maxOffset - minOffset + 1) * 2)
            for offset in minOffset...maxOffset {
                values.append(offset)
            }
            for offset in stride(from: maxOffset - 1, through: minOffset, by: -1) {
                values.append(offset)
            }
            offsets = values
        } else {
            offsets = [0, 0]
        }

        return ScrollAnimationSource(
            unditheredPixels: unditheredPixels,
            sourceWidth: workingWidth,
            sourceHeight: workingHeight,
            targetWidth: targetWidth,
            targetHeight: targetHeight,
            baseViewport: scaledCrop,
            offsets: offsets,
            direction: direction
        )
    }

    func renderScrollAnimation(
        from source: ScrollAnimationSource,
        algorithm: DitherAlgorithm,
        mode: DitherMode = .rgb,
        levelsPerChannel: Int = 8,
        contrast: Double = 0
    ) -> [CGImage] {
        var pixels = source.unditheredPixels
        applyContrast(&pixels, amount: contrast)
        applyDither(
            &pixels,
            width: source.sourceWidth,
            height: source.sourceHeight,
            algorithm: algorithm,
            mode: mode,
            levelsPerChannel: levelsPerChannel
        )

        return source.offsets.compactMap { offset in
            let viewport = viewportRect(
                base: source.baseViewport,
                offset: offset,
                direction: source.direction
            )
            return extractFrame(
                from: pixels,
                sourceWidth: source.sourceWidth,
                viewport: viewport,
                targetWidth: source.targetWidth,
                targetHeight: source.targetHeight
            )
        }
    }

    /// Renders only the region the animation actually travels across (from the
    /// start viewport to the chosen end position) as a single still image, so the
    /// user judges exactly what will scroll over the LED bar — not the whole photo.
    func renderStrip(
        from source: ScrollAnimationSource,
        algorithm: DitherAlgorithm,
        mode: DitherMode = .rgb,
        levelsPerChannel: Int = 8,
        contrast: Double = 0
    ) -> CGImage? {
        var pixels = source.unditheredPixels
        applyContrast(&pixels, amount: contrast)
        applyDither(
            &pixels,
            width: source.sourceWidth,
            height: source.sourceHeight,
            algorithm: algorithm,
            mode: mode,
            levelsPerChannel: levelsPerChannel
        )

        let region = animatedRegion(for: source)
        return croppedImage(
            from: pixels,
            sourceWidth: source.sourceWidth,
            sourceHeight: source.sourceHeight,
            rect: region
        )
    }

    /// The union of every viewport position across the animation: the slice of
    /// the strip that is ever visible on the LED bar between start and end.
    private func animatedRegion(for source: ScrollAnimationSource) -> CGRect {
        let base = source.baseViewport
        let maxOffset = CGFloat(source.offsets.max() ?? 0)

        switch source.direction {
        case .down:
            return CGRect(x: base.minX, y: base.minY, width: base.width, height: base.height + maxOffset)
        case .up:
            return CGRect(x: base.minX, y: base.minY - maxOffset, width: base.width, height: base.height + maxOffset)
        case .right:
            return CGRect(x: base.minX, y: base.minY, width: base.width + maxOffset, height: base.height)
        case .left:
            return CGRect(x: base.minX - maxOffset, y: base.minY, width: base.width + maxOffset, height: base.height)
        }
    }

    /// Extracts an arbitrary integer-aligned rectangle from an RGBA pixel buffer.
    private func croppedImage(
        from pixels: [UInt8],
        sourceWidth: Int,
        sourceHeight: Int,
        rect: CGRect
    ) -> CGImage? {
        let x0 = max(0, Int(rect.minX.rounded()))
        let y0 = max(0, Int(rect.minY.rounded()))
        let x1 = min(sourceWidth, Int(rect.maxX.rounded()))
        let y1 = min(sourceHeight, Int(rect.maxY.rounded()))
        let w = x1 - x0
        let h = y1 - y0

        guard w > 0, h > 0 else {
            return makeCGImage(from: pixels, width: sourceWidth, height: sourceHeight)
        }

        var out = [UInt8]()
        out.reserveCapacity(w * h * 4)
        for row in y0..<y1 {
            let start = (row * sourceWidth + x0) * 4
            out.append(contentsOf: pixels[start..<(start + w * 4)])
        }
        return makeCGImage(from: out, width: w, height: h)
    }

    /// Adjusts contrast around mid-gray. `amount` ranges from -1 (flat) to 1
    /// (strong); 0 leaves the pixels untouched.
    private func applyContrast(_ pixels: inout [UInt8], amount: Double) {
        guard amount != 0 else { return }
        let factor = 1 + max(-1, min(1, amount))

        func adjust(_ value: UInt8) -> UInt8 {
            let scaled = (Double(value) - 128) * factor + 128
            return UInt8(clamping: Int(scaled.rounded()))
        }

        var index = 0
        let count = pixels.count
        while index + 2 < count {
            pixels[index] = adjust(pixels[index])
            pixels[index + 1] = adjust(pixels[index + 1])
            pixels[index + 2] = adjust(pixels[index + 2])
            index += 4
        }
    }

    // MARK: - Scaling

    /// Crops `sourceRect` from `image` and scales it to `width`×`height`.
    private func cropAndScaleToSize(
        _ image: CGImage,
        sourceRect: CGRect,
        width: Int,
        height: Int
    ) -> CGImage? {
        guard width > 0, height > 0 else { return nil }

        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let source = sourceRect.pixelAligned.intersection(bounds)
        guard source.width > 0, source.height > 0,
              let cropped = image.cropping(to: source) else {
            return nil
        }

        return drawScaled(cropped, width: width, height: height)
    }

    private func bicubicScaleToSize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        drawScaled(image, width: width, height: height)
    }

    /// Scales `image` into a fresh RGBA bitmap. Pure Core Graphics keeps the
    /// orientation (row 0 = top) consistent across the whole pipeline.
    private func drawScaled(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: Self.sRGB,
                bitmapInfo: Self.rgbaBitmapInfo
              ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    // MARK: - Dithering

    func floydSteinbergDither(
        _ image: CGImage,
        mode: DitherMode,
        levelsPerChannel: Int = 8
    ) -> CGImage? {
        guard var pixels = copyPixelData(from: image) else { return nil }
        applyDither(
            &pixels,
            width: image.width,
            height: image.height,
            algorithm: .floydSteinberg,
            mode: mode,
            levelsPerChannel: levelsPerChannel
        )
        return makeCGImage(from: pixels, width: image.width, height: image.height)
    }

    private func applyDither(
        _ pixels: inout [UInt8],
        width: Int,
        height: Int,
        algorithm: DitherAlgorithm,
        mode: DitherMode,
        levelsPerChannel: Int
    ) {
        switch algorithm {
        case .floydSteinberg:
            errorDiffusionDitherInPlace(
                &pixels,
                width: width,
                height: height,
                mode: mode,
                levelsPerChannel: levelsPerChannel,
                neighbors: Self.floydSteinbergNeighbors
            )
        case .atkinson:
            errorDiffusionDitherInPlace(
                &pixels,
                width: width,
                height: height,
                mode: mode,
                levelsPerChannel: levelsPerChannel,
                neighbors: Self.atkinsonNeighbors
            )
        case .ordered:
            orderedDitherInPlace(
                &pixels,
                width: width,
                height: height,
                mode: mode,
                levelsPerChannel: levelsPerChannel
            )
        }
    }

    private static let floydSteinbergNeighbors: [(Int, Int, Double)] = [
        (1, 0, 7.0 / 16.0),
        (-1, 1, 3.0 / 16.0),
        (0, 1, 5.0 / 16.0),
        (1, 1, 1.0 / 16.0)
    ]

    private static let atkinsonNeighbors: [(Int, Int, Double)] = [
        (1, 0, 1.0 / 8.0),
        (2, 0, 1.0 / 8.0),
        (-1, 1, 1.0 / 8.0),
        (0, 1, 1.0 / 8.0),
        (1, 1, 1.0 / 8.0),
        (0, 2, 1.0 / 8.0)
    ]

    private func errorDiffusionDitherInPlace(
        _ pixels: inout [UInt8],
        width: Int,
        height: Int,
        mode: DitherMode,
        levelsPerChannel: Int,
        neighbors: [(Int, Int, Double)]
    ) {
        let levels = max(2, levelsPerChannel)
        let step = 255.0 / Double(levels - 1)

        func quantize(_ value: Double) -> Double {
            (value / step).rounded() * step
        }

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let oldR = Double(pixels[index])
                let oldG = Double(pixels[index + 1])
                let oldB = Double(pixels[index + 2])

                let newR = quantize(oldR)
                let newG = quantize(oldG)
                let newB = quantize(oldB)

                let finalR: Double
                let finalG: Double
                let finalB: Double
                switch mode {
                case .rgb:
                    finalR = newR
                    finalG = newG
                    finalB = newB
                case .monochrome:
                    let gray = quantize(0.299 * newR + 0.587 * newG + 0.114 * newB)
                    finalR = gray
                    finalG = gray
                    finalB = gray
                }

                pixels[index] = UInt8(clamping: Int(finalR.rounded()))
                pixels[index + 1] = UInt8(clamping: Int(finalG.rounded()))
                pixels[index + 2] = UInt8(clamping: Int(finalB.rounded()))
                pixels[index + 3] = 255

                let errR = oldR - finalR
                let errG = oldG - finalG
                let errB = oldB - finalB

                distributeError(
                    pixels: &pixels,
                    width: width,
                    height: height,
                    x: x,
                    y: y,
                    error: (errR, errG, errB),
                    neighbors: neighbors
                )
            }
        }
    }

    private func orderedDitherInPlace(
        _ pixels: inout [UInt8],
        width: Int,
        height: Int,
        mode: DitherMode,
        levelsPerChannel: Int
    ) {
        let levels = max(2, levelsPerChannel)
        let step = 255.0 / Double(levels - 1)

        func quantize(_ value: Double, threshold: Double) -> Double {
            let adjusted = value + (threshold - 0.5) * step
            return (adjusted / step).rounded() * step
        }

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let threshold = (Double(Self.bayer4x4[y % 4][x % 4]) + 0.5) / 16.0

                let oldR = Double(pixels[index])
                let oldG = Double(pixels[index + 1])
                let oldB = Double(pixels[index + 2])

                let newR = quantize(oldR, threshold: threshold)
                let newG = quantize(oldG, threshold: threshold)
                let newB = quantize(oldB, threshold: threshold)

                switch mode {
                case .rgb:
                    pixels[index] = UInt8(clamping: Int(newR.rounded()))
                    pixels[index + 1] = UInt8(clamping: Int(newG.rounded()))
                    pixels[index + 2] = UInt8(clamping: Int(newB.rounded()))
                case .monochrome:
                    let gray = quantize(0.299 * newR + 0.587 * newG + 0.114 * newB, threshold: threshold)
                    let value = UInt8(clamping: Int(gray.rounded()))
                    pixels[index] = value
                    pixels[index + 1] = value
                    pixels[index + 2] = value
                }
                pixels[index + 3] = 255
            }
        }
    }

    // MARK: - Private helpers

    private struct ScrollRange {
        let minOffset: Int
        let maxOffset: Int
    }

    private func sourceStripRect(
        crop: CGRect,
        imageSize: CGSize,
        direction: ScrollDirection
    ) -> CGRect {
        let bounds = CGRect(origin: .zero, size: imageSize)

        switch direction {
        case .right:
            return CGRect(
                x: crop.minX,
                y: crop.minY,
                width: imageSize.width - crop.minX,
                height: crop.height
            ).intersection(bounds)
        case .left:
            return CGRect(
                x: 0,
                y: crop.minY,
                width: crop.maxX,
                height: crop.height
            ).intersection(bounds)
        case .down:
            return CGRect(
                x: crop.minX,
                y: crop.minY,
                width: crop.width,
                height: imageSize.height - crop.minY
            ).intersection(bounds)
        case .up:
            return CGRect(
                x: crop.minX,
                y: 0,
                width: crop.width,
                height: crop.maxY
            ).intersection(bounds)
        }
    }

    private func scaledCropRect(
        crop: CGRect,
        sourceStrip: CGRect,
        stripScale: CGFloat,
        targetWidth: Int,
        targetHeight: Int
    ) -> CGRect {
        CGRect(
            x: (crop.minX - sourceStrip.minX) * stripScale,
            y: (crop.minY - sourceStrip.minY) * stripScale,
            width: CGFloat(targetWidth),
            height: CGFloat(targetHeight)
        ).integral
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

    private func extractFrame(
        from pixels: [UInt8],
        sourceWidth: Int,
        viewport: CGRect,
        targetWidth: Int,
        targetHeight: Int
    ) -> CGImage? {
        let x = Int(viewport.minX)
        let y = Int(viewport.minY)
        let sourceHeight = pixels.count / (sourceWidth * 4)
        guard x >= 0, y >= 0,
              x + targetWidth <= sourceWidth,
              y + targetHeight <= sourceHeight else {
            return nil
        }

        var frameData = [UInt8]()
        frameData.reserveCapacity(targetWidth * targetHeight * 4)
        for row in y..<(y + targetHeight) {
            let start = (row * sourceWidth + x) * 4
            frameData.append(contentsOf: pixels[start..<(start + targetWidth * 4)])
        }
        return makeCGImage(from: frameData, width: targetWidth, height: targetHeight)
    }

    /// Reads straight sRGB RGBA bytes (row 0 = top scanline), matching the
    /// memory layout produced by `makeCGImage` so no flips are ever needed.
    private func copyPixelData(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: Self.sRGB,
            bitmapInfo: Self.rgbaBitmapInfo
        ) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    private func makeCGImage(from pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        guard pixels.count == width * height * 4,
              let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            return nil
        }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: Self.sRGB,
            bitmapInfo: CGBitmapInfo(rawValue: Self.rgbaBitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private func distributeError(
        pixels: inout [UInt8],
        width: Int,
        height: Int,
        x: Int,
        y: Int,
        error: (Double, Double, Double),
        neighbors: [(Int, Int, Double)]
    ) {
        func addError(to px: Int, factor: Double) {
            guard px >= 0, px + 2 < pixels.count else { return }
            let r = Double(pixels[px]) + error.0 * factor
            let g = Double(pixels[px + 1]) + error.1 * factor
            let b = Double(pixels[px + 2]) + error.2 * factor
            pixels[px] = UInt8(clamping: Int(r.rounded()))
            pixels[px + 1] = UInt8(clamping: Int(g.rounded()))
            pixels[px + 2] = UInt8(clamping: Int(b.rounded()))
        }

        for (dx, dy, factor) in neighbors {
            let cx = x + dx
            let cy = y + dy
            guard cx >= 0, cx < width, cy >= 0, cy < height else { continue }
            addError(to: (cy * width + cx) * 4, factor: factor)
        }
    }
}

private extension CGRect {
    var pixelAligned: CGRect {
        CGRect(
            x: floor(origin.x),
            y: floor(origin.y),
            width: max(1, ceil(width)),
            height: max(1, ceil(height))
        )
    }

    func scaled(from sourceSize: CGSize, to targetSize: CGSize) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return self }
        let sx = targetSize.width / sourceSize.width
        let sy = targetSize.height / sourceSize.height
        return CGRect(
            x: origin.x * sx,
            y: origin.y * sy,
            width: width * sx,
            height: height * sy
        )
    }
}
