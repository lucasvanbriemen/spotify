import SwiftUI
import CoreGraphics

/// Extract a small palette of representative colors from album art for the
/// ambient gradient. Downscales the image and samples a grid of pixels,
/// biasing toward saturated, frequently occurring colors. Returns a neutral
/// fallback pair if anything goes wrong.
func dominantColors(from cgImage: CGImage, count: Int = 3) -> [Color] {
    let size = 24
    let bytesPerPixel = 4
    let bytesPerRow = size * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: size * size * bytesPerPixel)

    guard let context = CGContext(
        data: &pixels,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return neutralPalette
    }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

    // Bucket colors into a coarse grid and tally weighted frequency.
    var buckets: [Int: (r: Double, g: Double, b: Double, weight: Double, count: Double)] = [:]

    for i in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
        let r = Double(pixels[i]) / 255.0
        let g = Double(pixels[i + 1]) / 255.0
        let b = Double(pixels[i + 2]) / 255.0

        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let saturation = maxC == 0 ? 0 : (maxC - minC) / maxC
        // Weight saturated, mid-bright colors higher so backgrounds aren't flat gray.
        let weight = 0.2 + saturation * 1.3

        // Quantize to a 4 levels-per-channel key.
        let key = (Int(r * 3.99) << 6) | (Int(g * 3.99) << 3) | Int(b * 3.99)
        var bucket = buckets[key] ?? (0, 0, 0, 0, 0)
        bucket.r += r
        bucket.g += g
        bucket.b += b
        bucket.weight += weight
        bucket.count += 1
        buckets[key] = bucket
    }

    let sorted = buckets.values.sorted { $0.weight > $1.weight }
    guard !sorted.isEmpty else { return neutralPalette }

    let colors = sorted.prefix(count).map { bucket in
        Color(
            red: bucket.r / bucket.count,
            green: bucket.g / bucket.count,
            blue: bucket.b / bucket.count
        )
    }

    // Need at least two stops for a gradient.
    if colors.count == 1 {
        return [colors[0], colors[0].opacity(0.4)]
    }
    return colors
}

private let neutralPalette: [Color] = [
    Color(red: 0.15, green: 0.16, blue: 0.20),
    Color(red: 0.08, green: 0.08, blue: 0.10)
]
