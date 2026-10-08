import AppKit
import ApplicationServices
import BarloomCore
import CoreGraphics
import Foundation

enum MenuBarActivationError: Error, LocalizedError {
    case permissionRequired, itemExited, unsupported, moveUnsupported
    var errorDescription: String? {
        switch self {
        case .permissionRequired: "Allow Accessibility in Menu Bar settings to click other apps’ icons."
        case .itemExited: "This icon has changed or its app has exited. Open the bar again to refresh it."
        case .unsupported: "macOS could not open this icon. Try opening it from Arrange mode."
        case .moveUnsupported: "macOS did not move this icon. Its previous position has been kept."
        }
    }
}

actor MenuBarActivation {
    static func isClickable(_ item: MenuBarWindow, on screen: CGRect) -> Bool {
        item.isIconSized && screen.contains(CGPoint(x: item.frame.midX, y: item.frame.midY))
    }

    func move(_ recorded: MenuBarWindow, nextTo recordedAnchor: MenuBarWindow, before: Bool) async throws {
        guard AXIsProcessTrusted() else { throw MenuBarActivationError.permissionRequired }
        let windows = await MenuBarCatalog().windows()
        guard let item = windows.first(where: { $0.id == recorded.id && $0.ownerPID == recorded.ownerPID }),
              let anchor = windows.first(where: { $0.id == recordedAnchor.id }), item.isIconSized else { throw MenuBarActivationError.itemExited }
        if before && item.frame.maxX <= anchor.frame.minX + 2 { return }
        if !before && item.frame.minX >= anchor.frame.maxX - 2 { return }
        let destination = CGPoint(x: before ? anchor.frame.minX + 1 : anchor.frame.maxX - 1, y: anchor.frame.midY)
        let payloads = await Self.moveEventData(item: item, anchor: anchor, destination: destination)
        guard payloads.count == 3 else { throw MenuBarActivationError.moveUnsupported }
        for (index, payload) in payloads.enumerated() {
            guard let event = CGEvent(withDataAllocator: nil, data: payload as CFData) else { throw MenuBarActivationError.moveUnsupported }
            let targetID = index == 2 ? anchor.id : item.id
            event.flags = .maskCommand
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(item.ownerPID))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(targetID))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(targetID))
            event.postToPid(item.ownerPID)
            try await Task.sleep(for: .milliseconds(40))
        }
        for _ in 0..<5 {
            try await Task.sleep(for: .milliseconds(120))
            let fresh = await MenuBarCatalog().windows()
            guard let moved = fresh.first(where: { $0.id == item.id }), let boundary = fresh.first(where: { $0.id == anchor.id }) else { throw MenuBarActivationError.itemExited }
            if before && moved.frame.maxX <= boundary.frame.minX + 2 { return }
            if !before && moved.frame.minX >= boundary.frame.maxX - 2 { return }
        }
        throw MenuBarActivationError.moveUnsupported
    }

    @MainActor
    private static func moveEventData(item: MenuBarWindow, anchor: MenuBarWindow, destination: CGPoint) -> [Data] {
        let types: [NSEvent.EventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        return types.enumerated().compactMap { index, type in
            let window = index == 2 ? anchor : item
            guard let native = NSEvent.mouseEvent(with: type, location: CGPoint(x: window.frame.width / 2, y: window.frame.height / 2),
                                                  modifierFlags: [.command], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: Int(window.id), context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
                  let event = native.cgEvent else { return nil }
            event.location = index == 0 ? CGPoint(x: item.frame.midX, y: item.frame.midY) : destination
            guard let data = event.data else { return nil }
            return data as Data
        }
    }

    func activate(_ recorded: MenuBarWindow, rightClick: Bool, visibleBounds: CGRect?) async throws {
        guard AXIsProcessTrusted() else { throw MenuBarActivationError.permissionRequired }
        var item: MenuBarWindow?
        // The spacer was just collapsed. Let WindowServer lay out the real item
        // before clicking it; a click on its hidden/offscreen frame is ignored.
        for _ in 0..<12 {
            let current = await MenuBarCatalog().windows()
            item = current.first(where: {
                $0.id == recorded.id && $0.ownerPID == recorded.ownerPID &&
                $0.title == recorded.title && $0.isIconSized
            })
            if let item, visibleBounds.map({ Self.isClickable(item, on: $0) }) != false { break }
            try await Task.sleep(for: .milliseconds(80))
        }
        guard let item else { throw MenuBarActivationError.itemExited }
        let isVisible = visibleBounds.map { Self.isClickable(item, on: $0) } != false
        if !rightClick && !isVisible { throw MenuBarActivationError.unsupported }
        // Prefer the app's supported accessibility action. Scan only its extra menu bar,
        // never document windows, text fields, or other application content.
        let appPIDs = await MainActor.run {
            NSRunningApplication.runningApplications(withBundleIdentifier: item.title).map(\.processIdentifier)
        }
        for pid in Array(Set(appPIDs + [item.ownerPID])).sorted(by: { ($0 == item.ownerPID ? 1 : 0) < ($1 == item.ownerPID ? 1 : 0) }) {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.5)
            if let element = matchingExtra(in: app, frame: item.frame, allowSingleItem: pid != item.ownerPID) {
                let action = rightClick ? kAXShowMenuAction : kAXPressAction
                if AXUIElementPerformAction(element, action as CFString) == .success { return }
            }
        }
        if rightClick && !isVisible {
            // A hidden status item's window can remain just outside the display
            // even after the spacer contracts. Address the item's window in its
            // owning process instead of clicking an unrelated screen position.
            try await postWindowTargetedRightClick(to: item)
            return
        }
        guard isVisible else { throw MenuBarActivationError.unsupported }
        // Some status extras expose no AXPress. Send a real session mouse event
        // to the now-visible item so WindowServer can route its native menu.
        let point = CGPoint(x: item.frame.midX, y: item.frame.midY)
        let button: CGMouseButton = rightClick ? .right : .left
        let downType: CGEventType = rightClick ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = rightClick ? .rightMouseUp : .leftMouseUp
        guard let down = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: point, mouseButton: button),
              let up = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: point, mouseButton: button) else {
            throw MenuBarActivationError.unsupported
        }
        for event in [down, up] {
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(item.ownerPID))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(item.id))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(item.id))
            event.setIntegerValueField(.mouseEventClickState, value: 1)
        }
        down.post(tap: .cgSessionEventTap)
        try await Task.sleep(for: .milliseconds(35))
        up.post(tap: .cgSessionEventTap)
    }

    private func postWindowTargetedRightClick(to item: MenuBarWindow) async throws {
        let payloads = await Self.rightClickEventData(for: item)
        guard payloads.count == 2 else { throw MenuBarActivationError.unsupported }
        for payload in payloads {
            guard let event = CGEvent(withDataAllocator: nil, data: payload as CFData) else {
                throw MenuBarActivationError.unsupported
            }
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(item.ownerPID))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(item.id))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(item.id))
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.postToPid(item.ownerPID)
            try await Task.sleep(for: .milliseconds(35))
        }
    }

    @MainActor
    private static func rightClickEventData(for item: MenuBarWindow) -> [Data] {
        [NSEvent.EventType.rightMouseDown, .rightMouseUp].compactMap { type in
            guard let native = NSEvent.mouseEvent(with: type,
                                                  location: CGPoint(x: item.frame.width / 2, y: item.frame.height / 2),
                                                  modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: Int(item.id), context: nil, eventNumber: 0,
                                                  clickCount: 1, pressure: 1),
                  let event = native.cgEvent else { return nil }
            event.location = CGPoint(x: item.frame.midX, y: item.frame.midY)
            guard let data = event.data else { return nil }
            return data as Data
        }
    }

    private func matchingExtra(in app: AXUIElement, frame: CGRect, allowSingleItem: Bool) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXExtrasMenuBarAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let root = unsafeDowncast(value, to: AXUIElement.self)
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var pressableItems: [AXUIElement] = []
        var inspected = 0
        while !queue.isEmpty && inspected < 128 {
            let (element, depth) = queue.removeFirst()
            AXUIElementSetMessagingTimeout(element, 0.2)
            inspected += 1
            var role: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
               role as? String == kAXMenuBarItemRole as String { pressableItems.append(element) }
            var positionValue: CFTypeRef?
            var sizeValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
               AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
               let positionValue, let sizeValue,
               CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() {
                var position = CGPoint.zero
                var size = CGSize.zero
                let positionAX = unsafeDowncast(positionValue, to: AXValue.self)
                let sizeAX = unsafeDowncast(sizeValue, to: AXValue.self)
                if AXValueGetValue(positionAX, .cgPoint, &position), AXValueGetValue(sizeAX, .cgSize, &size),
                   abs(position.x - frame.minX) < 8, abs(position.y - frame.minY) < 8,
                   abs(size.width - frame.width) < 20 { return element }
            }
            guard depth < 3 else { continue }
            var childrenValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
               let children = childrenValue as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(64).map { ($0, depth + 1) })
            }
        }
        return allowSingleItem && pressableItems.count == 1 ? pressableItems.first : nil
    }
}
