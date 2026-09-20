// Regenerate the source icon: swift tools/make-icon.swift Sources/MacZ/Resources/AppIcon.icns
import AppKit

guard CommandLine.arguments.count == 2 else { fatalError("Usage: swift tools/make-icon.swift output.icns") }
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = AffineTransform(scale: Double(pixels) / 1024)
        (transform as NSAffineTransform).concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 198, yRadius: 198)
        NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.43, blue: 0.93, alpha: 1), ending: NSColor(srgbRed: 0.10, green: 0.23, blue: 0.65, alpha: 1))!.draw(in: background, angle: -90)
        NSColor.white.withAlphaComponent(0.78).setStroke()
        let pins = NSBezierPath()
        pins.lineWidth = 20
        pins.lineCapStyle = .round
        for position in stride(from: 372.0, through: 652.0, by: 70) {
            pins.move(to: NSPoint(x: position, y: 230)); pins.line(to: NSPoint(x: position, y: 300))
            pins.move(to: NSPoint(x: position, y: 724)); pins.line(to: NSPoint(x: position, y: 794))
            pins.move(to: NSPoint(x: 230, y: position)); pins.line(to: NSPoint(x: 300, y: position))
            pins.move(to: NSPoint(x: 724, y: position)); pins.line(to: NSPoint(x: 794, y: position))
        }
        pins.stroke()
        let chip = NSBezierPath(roundedRect: NSRect(x: 300, y: 300, width: 424, height: 424), xRadius: 48, yRadius: 48)
        NSColor.white.withAlphaComponent(0.12).setFill(); chip.fill()
        NSColor.white.setStroke(); chip.lineWidth = 22; chip.stroke()
        let z = NSBezierPath()
        z.move(to: NSPoint(x: 415, y: 610)); z.line(to: NSPoint(x: 609, y: 610))
        z.line(to: NSPoint(x: 415, y: 414)); z.line(to: NSPoint(x: 609, y: 414))
        z.lineWidth = 38; z.lineJoinStyle = .round; z.lineCapStyle = .round; z.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", directory.path, "-o", destination.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
