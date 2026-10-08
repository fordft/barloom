import BarloomCore
import BarloomMenuBarNative
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct CapturedMenuBarIcon: Sendable, Identifiable {
    var id: UInt32 { window.id }
    let window: MenuBarWindow
    let png: Data?
}

actor MenuBarCatalog {
    func windows() -> [MenuBarWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let id = entry[kCGWindowNumber as String] as? UInt32,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  let layer = entry[kCGWindowLayer as String] as? Int, layer == 25,
                  let dictionary = entry[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return nil }
            return MenuBarWindow(id: id, ownerPID: pid, ownerName: entry[kCGWindowOwnerName as String] as? String ?? "Application",
                                 title: entry[kCGWindowName as String] as? String ?? "", frame: frame, layer: layer)
        }
    }

    func capture(_ windows: [MenuBarWindow]) -> [CapturedMenuBarIcon] {
        guard CGPreflightScreenCaptureAccess() else { return [] }
        return windows.prefix(256).map { window in
            guard window.isIconSized, window.layer == 25, let image = BRLCopyStatusWindowImage(window.id),
                  image.width <= 1_024, image.height <= 256 else {
                return CapturedMenuBarIcon(window: window, png: nil)
            }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
                return CapturedMenuBarIcon(window: window, png: nil)
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return CapturedMenuBarIcon(window: window, png: nil) }
            return CapturedMenuBarIcon(window: window, png: data as Data)
        }
    }
}
