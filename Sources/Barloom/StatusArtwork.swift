import AppKit
import BarloomCore

/// Original vector artwork. Frames are drawn once and reused by the menu bar animation.
@MainActor
enum StatusArtwork {
    static func brandImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 20))
        image.lockFocus()
        NSColor.black.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2.1
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: 5, y: 3))
        path.line(to: NSPoint(x: 5, y: 17))
        path.move(to: NSPoint(x: 5, y: 10))
        path.curve(to: NSPoint(x: 16, y: 10), controlPoint1: NSPoint(x: 9, y: 19), controlPoint2: NSPoint(x: 16, y: 18))
        path.curve(to: NSPoint(x: 5, y: 3), controlPoint1: NSPoint(x: 19, y: 1), controlPoint2: NSPoint(x: 10, y: 0))
        path.move(to: NSPoint(x: 9, y: 8))
        path.curve(to: NSPoint(x: 19, y: 17), controlPoint1: NSPoint(x: 11, y: 8), controlPoint2: NSPoint(x: 17, y: 9))
        path.stroke()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    static func frames(for character: RunnerCharacter) -> [NSImage] {
        (0..<8).map { image(for: character, frame: $0) }
    }

    static func image(for character: RunnerCharacter, frame: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: 26, height: 20))
        image.lockFocus()
        NSColor.black.setFill()
        NSColor.black.setStroke()
        let phase = Double(frame % 8) / 8 * .pi * 2
        switch character {
        case .cat:
            let bounce = sin(phase * 2) * 0.7
            NSBezierPath(ovalIn: NSRect(x: 6, y: 7 + bounce, width: 12, height: 7)).fill()
            NSBezierPath(ovalIn: NSRect(x: 15, y: 10 + bounce, width: 7, height: 7)).fill()
            let ears = NSBezierPath()
            ears.move(to: NSPoint(x: 16, y: 15 + bounce))
            ears.line(to: NSPoint(x: 16, y: 19 + bounce))
            ears.line(to: NSPoint(x: 19, y: 16 + bounce))
            ears.move(to: NSPoint(x: 19, y: 16 + bounce))
            ears.line(to: NSPoint(x: 22, y: 19 + bounce))
            ears.line(to: NSPoint(x: 22, y: 14 + bounce))
            ears.fill()
            let tail = NSBezierPath()
            tail.lineWidth = 2.1
            tail.lineCapStyle = .round
            tail.move(to: NSPoint(x: 8, y: 11 + bounce))
            tail.curve(to: NSPoint(x: 2, y: 15 + sin(phase)), controlPoint1: NSPoint(x: 1, y: 10), controlPoint2: NSPoint(x: 5, y: 17))
            tail.stroke()
            for index in 0..<4 {
                let offset = Double(index) * .pi / 1.5
                let hipX = index < 2 ? 8.0 : 16.0
                let leg = NSBezierPath()
                leg.lineWidth = 1.8
                leg.lineCapStyle = .round
                leg.move(to: NSPoint(x: hipX, y: 9 + bounce))
                leg.line(to: NSPoint(x: hipX + sin(phase + offset) * 3, y: 4 + max(0, cos(phase + offset)) * 2))
                leg.stroke()
            }
        case .orbit:
            let track = NSBezierPath(ovalIn: NSRect(x: 4, y: 3, width: 18, height: 14))
            track.lineWidth = 1.2
            track.stroke()
            NSBezierPath(ovalIn: NSRect(x: 10, y: 7, width: 6, height: 6)).fill()
            NSBezierPath(ovalIn: NSRect(x: 11 + cos(phase) * 9, y: 8 + sin(phase) * 7, width: 4, height: 4)).fill()
        case .pulse:
            for index in 0..<5 {
                let height = 4 + (sin(phase + Double(index) * 0.9) + 1) * 5
                NSBezierPath(roundedRect: NSRect(x: Double(index) * 4.5 + 3, y: (20 - height) / 2, width: 2.6, height: height), xRadius: 1.3, yRadius: 1.3).fill()
            }
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
