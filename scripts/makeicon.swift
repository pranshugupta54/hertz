import AppKit

// Draws the Hertz app icon: a flat dark rounded square with a green
// heartbeat/ECG pulse. No gradients.
func drawIcon(_ s: CGFloat, into ctx: CGContext) {
    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

    let pad = s * 0.085
    let rect = CGRect(x: pad, y: pad, width: s - 2 * pad, height: s - 2 * pad)
    let radius = rect.width * 0.225
    let bg = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius,
                    transform: nil)

    ctx.saveGState()
    ctx.addPath(bg)
    ctx.setFillColor(CGColor(red: 0.086, green: 0.094, blue: 0.106, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bg)
    ctx.clip()
    let mid = s / 2
    let x0 = rect.minX
    let w = rect.width
    let amp = rect.height * 0.30
    // (x fraction, y offset as fraction of amplitude) — a single pulse.
    let pts: [(CGFloat, CGFloat)] = [
        (0.00, 0.0), (0.28, 0.0), (0.38, -0.18), (0.47, 0.92),
        (0.55, -1.0), (0.63, 0.22), (0.72, 0.0), (1.00, 0.0),
    ]
    let line = CGMutablePath()
    for (i, p) in pts.enumerated() {
        let cp = CGPoint(x: x0 + p.0 * w, y: mid + p.1 * amp)
        if i == 0 { line.move(to: cp) } else { line.addLine(to: cp) }
    }
    ctx.addPath(line)
    ctx.setStrokeColor(CGColor(red: 0.20, green: 0.80, blue: 0.55, alpha: 1))
    ctx.setLineWidth(s * 0.052)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()
}

let targets: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

let dir = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

for (name, px) in targets {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let gctx = NSGraphicsContext(bitmapImageRep: rep)
    else { continue }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx
    drawIcon(CGFloat(px), into: gctx.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
    }
}
print("iconset written to \(dir)")
