import AppKit
import BarloomCore
import CoreGraphics

enum MenuBarDisplay {
    /// AppKit does not guarantee that the first screen is the Quartz primary display.
    static var primaryDisplayTop: CGFloat {
        let primaryID = CGMainDisplayID()
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[key] as? NSNumber)?.uint32Value == primaryID
        }) {
            return screen.frame.maxY
        }
        return NSScreen.main?.frame.maxY ?? NSScreen.screens.first?.frame.maxY ?? 0
    }

    /// Status windows can sit a few dozen points away from the screen geometry
    /// reported by AppKit, especially on displays above the primary display.
    static func statusRowTop(on screen: NSScreen, windows: [MenuBarWindow], primaryDisplayTop: CGFloat) -> CGFloat {
        let expected = MenuBarGeometry.quartzRect(fromAppKit: screen.frame, primaryDisplayTop: primaryDisplayTop).minY
        return MenuBarGeometry.statusRowTop(expected: expected,
                                            screenX: screen.frame.minX..<screen.frame.maxX,
                                            windows: windows,
                                            identifier: Bundle.main.bundleIdentifier ?? "com.barloom.app")
    }
}
