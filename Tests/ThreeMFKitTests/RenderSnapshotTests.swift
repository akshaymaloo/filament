import XCTest
@testable import ThreeMFKit
#if canImport(SceneKit)
import SceneKit
import Metal
import AppKit

/// Offscreen SceneKit render smoke tests, using the same rendering path as
/// `ThumbnailExtension/ThumbnailProvider`: `BuildPlate.makeScene` +
/// `SCNRenderer.snapshot`. These are intentionally tolerant (no pixel-exact
/// golden images) — they just guard against gross regressions (a blank
/// frame, an object rendered off-center or filling/missing the whole
/// viewport, or a multi-color plate losing its per-filament coloring).
final class RenderSnapshotTests: XCTestCase {
    private static let size = 256

    private struct RGBAImage {
        let width: Int
        let height: Int
        let pixels: [UInt8] // RGBA8, row-major, top-left origin

        func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            let i = (y * width + x) * 4
            return (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
        }
    }

    /// Renders `plate` offscreen at `size`x`size` using the same
    /// `SCNRenderer` setup `ThumbnailProvider` uses. Returns `nil` (callers
    /// should `throw XCTSkip`) when there's no usable Metal device, e.g. some
    /// CI VMs.
    private func renderOffscreen(_ plate: BuildPlate, style: PreviewStyle = .default, size: Int = RenderSnapshotTests.size) -> RGBAImage? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }

        let scene = plate.makeScene(style: style)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = scene.previewCameraNode

        let pixelSize = CGSize(width: size, height: size)
        let nsImage = renderer.snapshot(atTime: 0, with: pixelSize, antialiasingMode: .multisampling4X)
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    private func colorDistance(_ a: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), _ b: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Int {
        abs(Int(a.r) - Int(b.r)) + abs(Int(a.g) - Int(b.g)) + abs(Int(a.b) - Int(b.b))
    }

    // MARK: - Single-color cube

    func testSingleColorCubeRendersNonBlankAndCentered() throws {
        let doc = try ThreeMFLoader().load(data: ThreeMFFixtureFactory.minimalCube(deflate: false))
        let plate = try XCTUnwrap(doc.plates.first)
        guard let image = renderOffscreen(plate) else {
            throw XCTSkip("No Metal device available (e.g. a headless CI VM); skipping offscreen render test.")
        }

        let background = image.pixel(x: 0, y: 0)
        var foregroundCount = 0
        var minX = image.width, maxX = -1, minY = image.height, maxY = -1
        let threshold = 24 // sum-of-channel-deltas; small enough to catch antialiased edges as background

        for y in 0..<image.height {
            for x in 0..<image.width {
                let p = image.pixel(x: x, y: y)
                if colorDistance(p, background) > threshold {
                    foregroundCount += 1
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }

        let totalPixels = image.width * image.height
        let foregroundFraction = Double(foregroundCount) / Double(totalPixels)
        XCTAssertGreaterThan(foregroundFraction, 0.02, "rendered frame looks blank (only \(foregroundFraction * 100)% of pixels differ from the background corner)")

        XCTAssertGreaterThanOrEqual(maxX, minX, "expected some foreground pixels")
        let objWidth = Double(maxX - minX + 1)
        let objHeight = Double(maxY - minY + 1)
        let widthFraction = objWidth / Double(image.width)
        let heightFraction = objHeight / Double(image.height)
        // `BuildPlate.makeScene`'s framing intentionally fills most of the
        // viewport (its footprint diagonal targets ~92% of the horizontal
        // FOV, its height ~80% of the vertical FOV), so the upper bound here
        // is deliberately loose — it's only meant to catch a gross "camera
        // stuck at zero distance" regression, not to enforce a margin.
        XCTAssertGreaterThan(widthFraction, 0.30, "object footprint too small: \(widthFraction)")
        XCTAssertLessThanOrEqual(widthFraction, 1.0, "object footprint exceeds the frame: \(widthFraction)")
        XCTAssertGreaterThan(heightFraction, 0.30, "object footprint too small: \(heightFraction)")
        XCTAssertLessThanOrEqual(heightFraction, 1.0, "object footprint exceeds the frame: \(heightFraction)")

        let centroidX = (Double(minX) + Double(maxX)) / 2
        let centroidY = (Double(minY) + Double(maxY)) / 2
        let centerX = Double(image.width) / 2
        let centerY = Double(image.height) / 2
        XCTAssertLessThan(abs(centroidX - centerX) / Double(image.width), 0.15, "object not horizontally centered")
        XCTAssertLessThan(abs(centroidY - centerY) / Double(image.height), 0.15, "object not vertically centered")
    }

    // MARK: - Multi-color plate

    func testMultiColorPlateRendersDistinctHueClusters() throws {
        let doc = try ThreeMFLoader().load(data: ThreeMFFixtureFactory.bambuMultiPlateProject())
        let plate = try XCTUnwrap(doc.plates.first) // palette: red / green / blue; plate 1 uses red+green
        guard let image = renderOffscreen(plate) else {
            throw XCTSkip("No Metal device available (e.g. a headless CI VM); skipping offscreen render test.")
        }

        let background = image.pixel(x: 0, y: 0)
        let threshold = 24
        // Quantize into 12 hue buckets (30° each); count buckets with a
        // meaningful number of foreground pixels.
        var bucketCounts = [Int](repeating: 0, count: 12)
        var foregroundCount = 0

        for y in 0..<image.height {
            for x in 0..<image.width {
                let p = image.pixel(x: x, y: y)
                guard colorDistance(p, background) > threshold else { continue }
                foregroundCount += 1
                let (h, s, v) = Self.rgbToHSV(r: p.r, g: p.g, b: p.b)
                // Low-saturation/very dark or bright pixels (shading, rim
                // highlights) don't carry reliable hue information; skip them
                // for cluster purposes but they still count as foreground.
                guard s > 0.25, v > 0.15, v < 0.98 else { continue }
                let bucket = min(11, Int(h / 30.0))
                bucketCounts[bucket] += 1
            }
        }

        XCTAssertGreaterThan(foregroundCount, 0, "rendered frame looks blank")
        let significantBuckets = bucketCounts.filter { $0 > Int(Double(foregroundCount) * 0.02) }
        XCTAssertGreaterThanOrEqual(significantBuckets.count, 2, "expected at least 2 distinct hue clusters for a red+green painted plate, got bucket histogram \(bucketCounts)")
    }

    private static func rgbToHSV(r: UInt8, g: UInt8, b: UInt8) -> (h: Double, s: Double, v: Double) {
        let rf = Double(r) / 255.0, gf = Double(g) / 255.0, bf = Double(b) / 255.0
        let maxV = max(rf, gf, bf), minV = min(rf, gf, bf)
        let delta = maxV - minV
        var h: Double = 0
        if delta > 0 {
            if maxV == rf { h = 60 * (((gf - bf) / delta).truncatingRemainder(dividingBy: 6)) }
            else if maxV == gf { h = 60 * (((bf - rf) / delta) + 2) }
            else { h = 60 * (((rf - gf) / delta) + 4) }
            if h < 0 { h += 360 }
        }
        let s = maxV == 0 ? 0 : delta / maxV
        return (h, s, maxV)
    }
}
#endif
