// Draws Filament's app icon (multicolor filament "f" extruded from a nozzle
// over a build plate) and writes every size of the AppIcon asset set plus the
// README icon. Run from the repo root:
//   swift scripts/make-app-icon.swift
import AppKit
import CoreGraphics

let S: CGFloat = 1024
func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff)/255, green: CGFloat((hex >> 8) & 0xff)/255, blue: CGFloat(hex & 0xff)/255, alpha: a)
}
// Centerline polylines (y-down coordinates)
func cubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, n: Int = 60) -> [CGPoint] {
    (0...n).map { i in
        let t = CGFloat(i)/CGFloat(n), u = 1-t
        return CGPoint(x: u*u*u*p0.x + 3*u*u*t*p1.x + 3*u*t*t*p2.x + t*t*t*p3.x,
                       y: u*u*u*p0.y + 3*u*u*t*p1.y + 3*u*t*t*p2.y + t*t*t*p3.y)
    }
}
func line(_ a: CGPoint, _ b: CGPoint, n: Int = 30) -> [CGPoint] { (0...n).map { i in let t = CGFloat(i)/CGFloat(n); return CGPoint(x: a.x+(b.x-a.x)*t, y: a.y+(b.y-a.y)*t) } }
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
let stem: [CGPoint] = line(P(492, 700), P(492, 400)) + cubic(P(492, 400), P(492, 230), P(600, 170), P(690, 196)).dropFirst() + cubic(P(690, 196), P(770, 220), P(790, 300), P(722, 322)).dropFirst()
let bar: [CGPoint] = line(P(330, 470), P(660, 470))
let loopBar: [CGPoint] = cubic(P(300, 458), P(360, 410), P(420, 430), P(492, 470)) + cubic(P(492, 470), P(570, 512), P(640, 520), P(700, 470)).dropFirst()

func offset(_ pts: [CGPoint], _ d: CGFloat) -> [CGPoint] {
    pts.indices.map { i in
        let a = pts[max(0, i-1)], b = pts[min(pts.count-1, i+1)]
        let dx = b.x-a.x, dy = b.y-a.y, l = max(0.0001, hypot(dx, dy))
        return P(pts[i].x - dy/l*d, pts[i].y + dx/l*d)
    }
}
func path(_ pts: [CGPoint]) -> CGPath { let p = CGMutablePath(); p.addLines(between: pts); return p }

func extend(_ pts: [CGPoint], _ d: CGFloat) -> [CGPoint] {
    func ext(_ a: CGPoint, _ b: CGPoint) -> CGPoint { let dx = a.x-b.x, dy = a.y-b.y, l = max(0.0001, hypot(dx, dy)); return P(a.x+dx/l*d, a.y+dy/l*d) }
    return [ext(pts[0], pts[1])] + pts + [ext(pts[pts.count-1], pts[pts.count-2])]
}
func stripes(_ ctx: CGContext, _ pts: [CGPoint], colors: [CGColor], width: CGFloat, gap: CGFloat = 0, outline: CGColor? = nil) {
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    let n = CGFloat(colors.count), sw = width/n
    if let outline { ctx.setStrokeColor(outline); ctx.setLineWidth(width + 20); ctx.addPath(path(pts)); ctx.strokePath() }
    ctx.saveGState()
    ctx.setLineWidth(width); ctx.addPath(path(pts)); ctx.replacePathWithStrokedPath(); ctx.clip()
    let long = extend(pts, width/2 + 4)
    ctx.setLineCap(.butt)
    for (i, col) in colors.enumerated() {
        let d = -width/2 + sw*(CGFloat(i)+0.5)
        ctx.setStrokeColor(col); ctx.setLineWidth(sw - gap + 0.8)
        ctx.addPath(path(offset(long, d))); ctx.strokePath()
    }
    ctx.restoreGState()
}
func gradientStroke(_ ctx: CGContext, _ pts: [CGPoint], width: CGFloat, colors: [CGColor], from: CGPoint, to: CGPoint) {
    ctx.saveGState()
    ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.setLineWidth(width)
    ctx.addPath(path(pts)); ctx.replacePathWithStrokedPath(); ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
func squircle() -> CGPath { CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil) }
func fillGradient(_ ctx: CGContext, _ colors: [CGColor], _ a: CGPoint, _ b: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: a, end: b, options: [])
}
func nozzle(_ ctx: CGContext, body: CGColor, tip: CGColor, ring: CGColor? = nil, gradient: [CGColor]? = nil) {
    let bodyR = CGRect(x: 432, y: 688, width: 120, height: 62)
    let cone = CGMutablePath(); cone.move(to: P(448, 748)); cone.addLine(to: P(536, 748)); cone.addLine(to: P(500, 812)); cone.addLine(to: P(484, 812)); cone.closeSubpath()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: bodyR, cornerWidth: 14, cornerHeight: 14, transform: nil))
    if let gradient { ctx.clip(); fillGradient(ctx, gradient, P(432, 0), P(552, 0)) } else { ctx.setFillColor(body); ctx.fillPath() }
    ctx.restoreGState()
    if let ring { ctx.setFillColor(ring); ctx.fill(CGRect(x: 432, y: 706, width: 120, height: 8)) }
    ctx.setFillColor(tip); ctx.addPath(cone); ctx.fillPath()
}
func render(_ name: String, _ draw: (CGContext) -> Void) {
    _ = name
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)
    // macOS-style drop shadow under the tile
    ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 28, color: c(0, 0.30))
    ctx.addPath(squircle()); ctx.setFillColor(c(0xffffff)); ctx.fillPath(); ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(squircle()); ctx.clip(); draw(ctx); ctx.restoreGState()
    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: name))
}
let orange = c(0xFF8A3D), yellow = c(0xFFC94A), blue = c(0x3D8BFF), teal = c(0x2EC4B6), pink = c(0xFF5D8F), purple = c(0x8B5CF6)

// B — Modern: midnight tile, glowing gradient tube, brushed nozzle
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "App/Filament/Assets.xcassets/AppIcon.appiconset"
let master = NSTemporaryDirectory() + "filament-icon-1024.png"
render(master) { ctx in
    fillGradient(ctx, [c(0x1B2A4A), c(0x0B1020)], P(0, 100), P(0, 924))
    ctx.setStrokeColor(c(0x5CC2DA, 0.18)); ctx.setLineWidth(3)
    for x in stride(from: 160, through: 880, by: 80) { ctx.move(to: P(CGFloat(x), 760)); ctx.addLine(to: P(512 + (CGFloat(x)-512)*1.6, 924)); ctx.strokePath() }
    for y in [790, 840, 900] { ctx.move(to: P(100, CGFloat(y))); ctx.addLine(to: P(924, CGFloat(y))); ctx.strokePath() }
    ctx.saveGState(); ctx.setShadow(offset: .zero, blur: 50, color: c(0xFF8A3D, 0.8))
    gradientStroke(ctx, stem, width: 112, colors: [c(0xFFB347), c(0xFF5D8F), c(0x8B5CF6), c(0x3DA9FF)], from: P(492, 700), to: P(760, 180))
    ctx.restoreGState()
    ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: 8), blur: 20, color: c(0, 0.5))
    gradientStroke(ctx, loopBar, width: 84, colors: [c(0xFFD25A), c(0xFF8A3D), c(0x3DA9FF)], from: P(280, 0), to: P(720, 0))
    ctx.restoreGState()
    // glass highlight on stem
    ctx.setStrokeColor(c(0xffffff, 0.35)); ctx.setLineWidth(14); ctx.setLineCap(.round)
    ctx.addPath(path(Array(offset(stem, -30)[8..<70]))); ctx.strokePath()
    nozzle(ctx, body: .black, tip: c(0xFF7A2E), ring: c(0x9AA6B8), gradient: [c(0x5B6578), c(0xD9DEE6), c(0x6B7588)])
    ctx.saveGState(); ctx.setShadow(offset: .zero, blur: 24, color: c(0xFF8A3D))
    ctx.setStrokeColor(c(0xFFB347)); ctx.setLineWidth(14); ctx.move(to: P(492, 834)); ctx.addLine(to: P(650, 834)); ctx.strokePath(); ctx.restoreGState()
}

// Downscale the 1024 master into every slot of the app icon set.
let masterImage = NSImage(contentsOfFile: master)!
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        masterImage.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let file = scale == 1 ? "icon_\(size).png" : "icon_\(size)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(file)"))
    }
}
try! FileManager.default.removeItem(atPath: "docs/images/icon.png")
try! FileManager.default.copyItem(atPath: "\(out)/icon_256@2x.png", toPath: "docs/images/icon.png")
print("Wrote app icon set to \(out) and docs/images/icon.png")
