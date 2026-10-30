// Renders the MacSlider app icon into an .iconset folder.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Background: rounded square with a deep blue-violet gradient.
    let inset = s * 0.1
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let background = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(
        starting: NSColor(srgbRed: 0.16, green: 0.20, blue: 0.45, alpha: 1),
        ending: NSColor(srgbRed: 0.33, green: 0.24, blue: 0.80, alpha: 1)
    )!.draw(in: background, angle: 90)

    // Three columns: the middle one in focus, the outer ones sliding off the edges.
    let columnHeight = tile.height * 0.56
    let y = tile.midY - columnHeight / 2
    let gap = tile.width * 0.05
    let middleWidth = tile.width * 0.40
    let sideWidth = tile.width * 0.30
    let radius = tile.width * 0.05
    let middle = NSRect(x: tile.midX - middleWidth / 2, y: y, width: middleWidth, height: columnHeight)
    let left = NSRect(x: middle.minX - gap - sideWidth, y: y, width: sideWidth, height: columnHeight)
    let right = NSRect(x: middle.maxX + gap, y: y, width: sideWidth, height: columnHeight)

    NSGraphicsContext.saveGraphicsState()
    background.addClip()
    NSColor.white.withAlphaComponent(0.35).setFill()
    NSBezierPath(roundedRect: left, xRadius: radius, yRadius: radius).fill()
    NSBezierPath(roundedRect: right, xRadius: radius, yRadius: radius).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.setFill()
    NSBezierPath(roundedRect: middle, xRadius: radius, yRadius: radius).fill()

    // Title bar strip on the focused column.
    NSColor(srgbRed: 0.33, green: 0.24, blue: 0.80, alpha: 0.25).setFill()
    let bar = NSRect(x: middle.minX, y: middle.maxY - columnHeight * 0.14, width: middle.width, height: columnHeight * 0.14)
    NSBezierPath(roundedRect: bar, xRadius: radius, yRadius: radius).fill()

    // Slide arrows below the strip.
    let arrowY = tile.minY + tile.height * 0.11
    let arrowSize = tile.width * 0.06
    NSColor.white.withAlphaComponent(0.9).setFill()
    for direction in [-1.0, 1.0] {
        let cx = tile.midX + CGFloat(direction) * tile.width * 0.12
        let path = NSBezierPath()
        path.move(to: NSPoint(x: cx + CGFloat(direction) * arrowSize, y: arrowY))
        path.line(to: NSPoint(x: cx - CGFloat(direction) * arrowSize * 0.6, y: arrowY + arrowSize))
        path.line(to: NSPoint(x: cx - CGFloat(direction) * arrowSize * 0.6, y: arrowY - arrowSize))
        path.close()
        path.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: output.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: output.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("Wrote \(output.path)")
