import CoreGraphics
import Foundation

public enum MenuBarSection: String, CaseIterable, Identifiable, Sendable {
    case hidden, alwaysHidden, all
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .hidden: "Hidden icons"
        case .alwaysHidden: "Always-hidden icons"
        case .all: "All hidden icons"
        }
    }
}

public struct MenuBarWindow: Equatable, Sendable, Identifiable {
    public let id: UInt32
    public let ownerPID: Int32
    public let ownerName: String
    public let title: String
    public let frame: CGRect
    public let layer: Int

    public init(id: UInt32, ownerPID: Int32, ownerName: String, title: String, frame: CGRect, layer: Int = 25) {
        self.id = id
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.title = title
        self.frame = frame
        self.layer = layer
    }

    public var isIconSized: Bool {
        frame.width.isFinite && frame.height.isFinite && frame.minX.isFinite && frame.minY.isFinite &&
        (8...240).contains(frame.width) && (12...48).contains(frame.height)
    }
}

public struct MenuBarDivider: Equatable, Sendable {
    public let windowID: UInt32
    public let frame: CGRect
    public let section: MenuBarSection
    public init(windowID: UInt32, frame: CGRect, section: MenuBarSection) {
        self.windowID = windowID
        self.frame = frame
        self.section = section
    }
}

public enum MenuBarGeometry {
    /// NSStatusItem rejects larger values with an Objective-C exception on macOS 26.
    public static let collapsedSpacerLength: CGFloat = 10_000
    /// Quartz has its origin at the primary display's top left; AppKit uses its bottom left.
    public static func quartzRect(fromAppKit rect: CGRect, primaryDisplayTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryDisplayTop - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Match a display's status row to its control window. AppKit's reported
    /// screen top may differ from the WindowServer row on external displays.
    public static func statusRowTop(expected: CGFloat, screenX: Range<CGFloat>,
                                    windows: [MenuBarWindow], identifier: String) -> CGFloat {
        let controls = windows.filter {
            $0.isIconSized && ($0.title.hasSuffix(".control") || $0.title == identifier) &&
            screenX.contains($0.frame.midX) && abs($0.frame.minY - expected) < 100
        }
        return controls.min { lhs, rhs in
            let lhsPriority = lhs.title.hasSuffix(".control") ? 0 : 1
            let rhsPriority = rhs.title.hasSuffix(".control") ? 0 : 1
            return (lhsPriority, abs(lhs.frame.minY - expected)) < (rhsPriority, abs(rhs.frame.minY - expected))
        }?.frame.minY ?? expected
    }

    /// Keep the entire shelf below the menu bar / camera housing, within this display.
    public static func shelfFrame(screen: CGRect, menuBarHeight: CGFloat, notchHeight: CGFloat,
                                  anchorX: CGFloat, desiredWidth: CGFloat, height: CGFloat = 52) -> CGRect {
        let margin: CGFloat = 12
        let width = min(max(1, screen.width - 2 * margin), max(180, desiredWidth))
        let left = min(screen.maxX - margin - width, max(screen.minX + margin, anchorX - width))
        let topInset = max(menuBarHeight, notchHeight)
        return CGRect(x: left, y: screen.maxY - topInset - 6 - height, width: width, height: height)
    }

    /// Assign offscreen icons to the closest divider on their right. This also separates
    /// replicated status items on displays that share the same vertical coordinate.
    public static func icons(_ windows: [MenuBarWindow], between dividers: [MenuBarDivider],
                             selectedDividerID: UInt32, section: MenuBarSection,
                             excludedIDs: Set<UInt32> = []) -> [MenuBarWindow] {
        guard let selected = dividers.first(where: { $0.windowID == selectedDividerID }) else { return [] }
        let rowDividers = dividers.filter { abs($0.frame.midY - selected.frame.midY) < 8 }
        let exclusions = excludedIDs.union(dividers.map(\.windowID))
        let selectedAlways = rowDividers.filter {
            $0.section == .alwaysHidden && $0.frame.maxX <= selected.frame.minX + 2
        }.max { $0.frame.maxX < $1.frame.maxX }

        return windows.filter { window in
            guard window.layer == 25, window.isIconSized, !exclusions.contains(window.id),
                  abs(window.frame.midY - selected.frame.midY) < 8 else { return false }
            let closest = rowDividers.filter { window.frame.maxX <= $0.frame.minX + 2 }
                .min { $0.frame.minX < $1.frame.minX }
            guard let closest else { return false }
            switch section {
            case .hidden: return closest.windowID == selected.windowID
            case .alwaysHidden: return closest.windowID == selectedAlways?.windowID
            case .all: return closest.windowID == selected.windowID || closest.windowID == selectedAlways?.windowID
            }
        }.sorted { ($0.frame.minX, $0.id) < ($1.frame.minX, $1.id) }
    }
}
