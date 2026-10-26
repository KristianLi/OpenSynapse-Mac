// Draws the app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift [preview.png]
import AppKit

let canvas: CGFloat = 1024
/// NSShadow works in device pixels and ignores the context scale, so blur and offset are
/// multiplied by the pixels-per-design-unit of the size being rendered.
var pixelScale: CGFloat = 1

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawIcon(in context: CGContext) {
    let s = canvas / 1024
    // macOS icon grid: the body sits inset on the 1024 canvas, with room for the drop shadow.
    let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 28 * pixelScale
    shadow.shadowOffset = NSSize(width: 0, height: -12 * pixelScale)
    shadow.set()
    color(0x111214).setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    bodyPath.addClip()
    NSGradient(colors: [color(0x2A2E34), color(0x0C0D0F)])!.draw(in: body, angle: -90)
    // Soft green glow behind the mouse.
    NSGradient(colors: [color(0x44D62C, 0.30), color(0x44D62C, 0)])!
        .draw(fromCenter: NSPoint(x: 512 * s, y: 470 * s), radius: 0,
              toCenter: NSPoint(x: 512 * s, y: 470 * s), radius: 400 * s, options: [])
    NSGraphicsContext.restoreGraphicsState()

    // Hairline highlight on the body edge.
    color(0xFFFFFF, 0.08).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 2 * s, dy: 2 * s), xRadius: 183 * s, yRadius: 183 * s)
    rim.lineWidth = 4 * s
    rim.stroke()

    // Mouse outline.
    let mouse = CGRect(x: 512 * s - 165 * s, y: 250 * s, width: 330 * s, height: 500 * s)
    let mousePath = NSBezierPath(roundedRect: mouse, xRadius: 165 * s, yRadius: 165 * s)
    let green = NSGradient(colors: [color(0x6CF54A), color(0x1FA84A)])!

    func strokeGlowing(_ path: NSBezierPath, width: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = color(0x44D62C, 0.75)
        glow.shadowBlurRadius = 26 * pixelScale
        glow.shadowOffset = .zero
        glow.set()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color(0x44D62C).setStroke()
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
        // Gradient pass on top of the glow.
        NSGraphicsContext.saveGraphicsState()
        let outline = path.copy() as! NSBezierPath
        outline.lineWidth = width
        let cgPath = outline.cgPathCompat.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
        context.addPath(cgPath)
        context.clip()
        green.draw(in: path.bounds.insetBy(dx: -width, dy: -width), angle: -90)
        NSGraphicsContext.restoreGraphicsState()
    }

    strokeGlowing(mousePath, width: 30 * s)

    // Button split and scroll wheel.
    let split = NSBezierPath()
    split.move(to: NSPoint(x: 512 * s, y: 750 * s))
    split.line(to: NSPoint(x: 512 * s, y: 640 * s))
    strokeGlowing(split, width: 22 * s)
    let wheel = NSBezierPath(roundedRect: CGRect(x: 512 * s - 22 * s, y: 560 * s, width: 44 * s, height: 86 * s),
                             xRadius: 22 * s, yRadius: 22 * s)
    strokeGlowing(wheel, width: 18 * s)

    // "Synapse": three linked nodes in the palm of the mouse.
    let nodes = [NSPoint(x: 512 * s, y: 470 * s), NSPoint(x: 440 * s, y: 350 * s), NSPoint(x: 584 * s, y: 350 * s)]
    let links = NSBezierPath()
    links.move(to: nodes[0]); links.line(to: nodes[1])
    links.line(to: nodes[2]); links.line(to: nodes[0])
    strokeGlowing(links, width: 12 * s)
    for node in nodes {
        let dot = NSBezierPath(ovalIn: CGRect(x: node.x - 30 * s, y: node.y - 30 * s, width: 60 * s, height: 60 * s))
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = color(0x44D62C, 0.9)
        glow.shadowBlurRadius = 24 * pixelScale
        glow.set()
        color(0x7DFF5C).setFill()
        dot.fill()
        NSGraphicsContext.restoreGraphicsState()
        color(0xE8FFE0).setFill()
        NSBezierPath(ovalIn: CGRect(x: node.x - 11 * s, y: node.y - 11 * s, width: 22 * s, height: 22 * s)).fill()
    }
}

extension NSBezierPath {
    var cgPathCompat: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for index in 0..<elementCount {
            switch element(at: index, associatedPoints: &points) {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo, .cubicCurveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo: path.addQuadCurve(to: points[1], control: points[0])
            case .closePath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    // One point per pixel, then a single scale from the 1024 design grid down to this size.
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = graphics
    graphics.imageInterpolation = .high
    let context = graphics.cgContext
    pixelScale = CGFloat(size) / canvas
    context.scaleBy(x: pixelScale, y: pixelScale)
    drawIcon(in: context)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
if CommandLine.arguments.count > 1 {
    try render(size: 1024).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
let resources = root.appendingPathComponent("Resources")
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")
