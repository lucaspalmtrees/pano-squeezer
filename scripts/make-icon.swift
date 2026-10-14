// Draws the app icon: a squeezed oval that becomes a circle. Run via scripts/make-icon.sh (macOS only).
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s, y: s)

    // Background: rounded square (macOS icon grid: 824 pt body inside 1024 canvas).
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bg = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGradient(colors: [NSColor(red: 0.10, green: 0.16, blue: 0.24, alpha: 1),
                        NSColor(red: 0.04, green: 0.07, blue: 0.11, alpha: 1)])!.draw(in: bg, angle: -90)

    let c = NSPoint(x: 512, y: 512)
    let r: CGFloat = 250
    // Squeezed oval (what the sensor records): dashed, muted.
    let oval = NSBezierPath(ovalIn: NSRect(x: c.x - r / 1.6, y: c.y - r, width: 2 * r / 1.6, height: 2 * r))
    oval.lineWidth = 22
    oval.setLineDash([34, 26], count: 2, phase: 0)
    NSColor(white: 1, alpha: 0.35).setStroke()
    oval.stroke()
    // Desqueezed circle: solid, warm.
    let circle = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    circle.lineWidth = 34
    NSColor(red: 1.0, green: 0.72, blue: 0.30, alpha: 1).setStroke()
    circle.stroke()
    // Small arrows left/right: "stretch".
    NSColor(red: 1.0, green: 0.72, blue: 0.30, alpha: 1).setFill()
    for dir: CGFloat in [-1, 1] {
        let tip = NSPoint(x: c.x + dir * 130, y: c.y)
        let p = NSBezierPath()
        p.move(to: tip)
        p.line(to: NSPoint(x: tip.x - dir * 60, y: tip.y + 44))
        p.line(to: NSPoint(x: tip.x - dir * 60, y: tip.y - 44))
        p.close()
        p.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! render(size).write(to: URL(fileURLWithPath: "\(outDir)/icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: URL(fileURLWithPath: "\(outDir)/icon_\(size)x\(size)@2x.png"))
}
print("Wrote \(outDir)")
