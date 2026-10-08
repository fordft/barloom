import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum CustomMenuBarIcon {
    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Barloom", isDirectory: true).appendingPathComponent("menu-bar-icon.png")
    }

    static func load(template: Bool) -> NSImage? {
        guard let image = NSImage(contentsOf: fileURL) else { return nil }
        return sized(image, template: template)
    }

    static func choose() throws -> NSImage? {
        let picker = NSOpenPanel()
        picker.title = "Choose a menu bar icon"
        picker.message = "Choose a PNG, JPEG, HEIC, or other supported image. Barloom keeps a small local copy."
        picker.allowedContentTypes = [.image]
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = false
        guard picker.runModal() == .OK, let url = picker.url else { return nil }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= 20_000_000,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 256
              ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        let bitmap = NSBitmapImageRep(cgImage: thumbnail)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: fileURL, options: .atomic)
        return sized(NSImage(cgImage: thumbnail, size: .zero), template: false)
    }

    private static func sized(_ image: NSImage, template: Bool) -> NSImage {
        let aspect = image.size.width / max(1, image.size.height)
        image.size = aspect >= 22 / 18 ? NSSize(width: 22, height: 22 / aspect) : NSSize(width: 18 * aspect, height: 18)
        image.isTemplate = template
        return image
    }
}
