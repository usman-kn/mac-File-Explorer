import AppKit

// Draws a blue tile with a yellow folder and writes an .iconset directory.
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let tile = NSBezierPath(roundedRect: NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8),
                            xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: NSColor(red: 0.20, green: 0.55, blue: 1.0, alpha: 1),
               ending: NSColor(red: 0.05, green: 0.28, blue: 0.75, alpha: 1))!.draw(in: tile, angle: -90)
    NSColor(red: 0.96, green: 0.66, blue: 0.12, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.22, y: s * 0.62, width: s * 0.22, height: s * 0.10),
                 xRadius: s * 0.03, yRadius: s * 0.03).fill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.22, y: s * 0.28, width: s * 0.56, height: s * 0.40),
                 xRadius: s * 0.04, yRadius: s * 0.04).fill()
    NSColor(red: 1.0, green: 0.82, blue: 0.30, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.22, y: s * 0.28, width: s * 0.56, height: s * 0.33),
                 xRadius: s * 0.04, yRadius: s * 0.04).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! render(base * scale).write(to: out.appendingPathComponent(name))
    }
}
