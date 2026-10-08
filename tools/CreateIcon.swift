import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift tools/CreateIcon.swift <iconset directory>")
}
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

func drawIcon(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(pixels) / 1_024)
    transform.concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 202, yRadius: 202)
    NSGradient(colors: [NSColor(red: 0.38, green: 0.26, blue: 0.76, alpha: 1), NSColor(red: 0.67, green: 0.56, blue: 1, alpha: 1)])!
        .draw(in: background, angle: 60)
    NSColor.white.withAlphaComponent(0.12).setStroke()
    background.lineWidth = 4
    background.stroke()
    NSColor.white.setStroke()
    let bloom = NSBezierPath()
    bloom.lineWidth = 70
    bloom.lineCapStyle = .round
    bloom.lineJoinStyle = .round
    bloom.move(to: NSPoint(x: 332, y: 278))
    bloom.line(to: NSPoint(x: 332, y: 756))
    bloom.move(to: NSPoint(x: 332, y: 505))
    bloom.curve(to: NSPoint(x: 685, y: 505), controlPoint1: NSPoint(x: 464, y: 790), controlPoint2: NSPoint(x: 688, y: 768))
    bloom.curve(to: NSPoint(x: 332, y: 278), controlPoint1: NSPoint(x: 775, y: 202), controlPoint2: NSPoint(x: 491, y: 187))
    bloom.move(to: NSPoint(x: 465, y: 440))
    bloom.curve(to: NSPoint(x: 778, y: 756), controlPoint1: NSPoint(x: 523, y: 440), controlPoint2: NSPoint(x: 719, y: 498))
    bloom.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let filename = "icon_\(points)x\(points)\(suffix).png"
        try drawIcon(pixels: points * scale).write(to: destination.appendingPathComponent(filename))
    }
}
