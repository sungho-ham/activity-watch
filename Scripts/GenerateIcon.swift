import AppKit

// Draw every icon size from vectors, including the small Finder representations.
func renderIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB,
                                       bytesPerRow: 0, bitsPerPixel: 0),
          let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)
    context.setShouldAntialias(true)

    let circle = NSBezierPath(ovalIn: NSRect(x: 88, y: 100, width: 848, height: 848))
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(srgbRed: 0.77, green: 0.37, blue: 0.25, alpha: 0.13)
    shadow.shadowBlurRadius = 24 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
    shadow.set()
    NSColor(srgbRed: 1, green: 0.88, blue: 0.74, alpha: 1).setFill()
    circle.fill()
    NSGraphicsContext.restoreGraphicsState()

    let lemon = NSColor(srgbRed: 1, green: 0.96, blue: 0.63, alpha: 1)
    let golden = NSColor(srgbRed: 1, green: 0.82, blue: 0.50, alpha: 1)
    let coral = NSColor(srgbRed: 1, green: 0.57, blue: 0.58, alpha: 1)
    NSGradient(colorsAndLocations: (lemon, 0), (golden, 0.48), (coral, 1))!
        .draw(in: circle, angle: -55)
    let rim = NSBezierPath(ovalIn: circle.bounds.insetBy(dx: 1.5, dy: 1.5))
    rim.lineWidth = 3
    NSColor.white.withAlphaComponent(0.5).setStroke()
    rim.stroke()

    // Stagger A and T around a clock-like slash, echoing ActivityWatch's layout.
    context.saveGState()
    context.translateBy(x: 512, y: 524)
    context.scaleBy(x: 0.92, y: 0.92)
    context.translateBy(x: -512, y: -524)
    let ink = NSColor(srgbRed: 0.46, green: 0.22, blue: 0.23, alpha: 1)
    ink.setStroke()
    let a = NSBezierPath()
    a.move(to: NSPoint(x: 230, y: 554))
    a.line(to: NSPoint(x: 350, y: 804))
    a.line(to: NSPoint(x: 470, y: 554))
    a.move(to: NSPoint(x: 278, y: 654))
    a.line(to: NSPoint(x: 422, y: 654))
    let t = NSBezierPath()
    t.move(to: NSPoint(x: 555, y: 500))
    t.line(to: NSPoint(x: 795, y: 500))
    t.move(to: NSPoint(x: 675, y: 500))
    t.line(to: NSPoint(x: 675, y: 260))
    // Shrink each letter around its own center to clear the slash and hub.
    for (letter, center) in [(a, NSPoint(x: 350, y: 679)), (t, NSPoint(x: 675, y: 380))] {
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: 0.90, y: 0.90)
        context.translateBy(x: -center.x, y: -center.y)
        letter.lineWidth = 48
        letter.lineCapStyle = .round
        letter.lineJoinStyle = .round
        letter.stroke()
        context.restoreGState()
    }

    let slash = NSBezierPath()
    slash.lineWidth = 28
    slash.lineCapStyle = .round
    slash.move(to: NSPoint(x: 282, y: 288))
    slash.line(to: NSPoint(x: 742, y: 760))
    slash.stroke()
    ink.setFill()
    NSBezierPath(ovalIn: NSRect(x: 486, y: 498, width: 52, height: 52)).fill()
    context.restoreGState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return png
}

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift Scripts/GenerateIcon.swift <output.iconset>")
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for density in [1, 2] {
        let suffix = density == 2 ? "@2x" : ""
        let png = try renderIcon(pixels: size * density)
        try png.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
print("Generated icon set: \(output.path)")
