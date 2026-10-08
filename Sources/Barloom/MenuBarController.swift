import AppKit
import BarloomCore
import Carbon
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let item: NSStatusItem
    private let popover = NSPopover()
    private var hiddenDivider: NSStatusItem?
    private var alwaysDivider: NSStatusItem?
    private var subscriptions: Set<AnyCancellable> = []
    private var animationTimer: Timer?
    private var presentationTask: Task<Void, Never>?
    private var frames: [NSImage] = []
    private var frame = 0
    private var character: RunnerCharacter?
    private var animationRate: Double = -1
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private lazy var shelf = IconShelfController(model: model)
    private let namespace: String
    private var fixtureItems: [NSStatusItem] = []

    init(model: AppModel) {
        self.model = model
        namespace = CommandLine.arguments.contains("--shelf-smoke-test") ? "Barloom.ShelfSmoke.Single" : "Barloom.Single"
        // One visible control, with a noninteractive spacer immediately to its left.
        // Set positions for our own new autosave names before creating the items.
        if !UserDefaults.standard.bool(forKey: "\(namespace).layoutInitialized") {
            UserDefaults.standard.set(0, forKey: "NSStatusItem Preferred Position \(namespace).control")
            UserDefaults.standard.set(1, forKey: "NSStatusItem Preferred Position \(namespace).hidden")
            UserDefaults.standard.set(true, forKey: "\(namespace).layoutInitialized")
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.autosaveName = "\(namespace).control"
        item.isVisible = true
        if let button = item.button {
            button.image = StatusArtwork.brandImage()
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Barloom")
            button.setAccessibilityHelp("Open hidden icons below the menu bar. Shift-click for the system monitor.")
            button.toolTip = "Click to open hidden icons · Shift-click for Quick Monitor"
        }
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 400, height: 510)
        popover.contentViewController = NSHostingController(rootView: MenuPopover().environmentObject(model))
        popover.delegate = self
        model.menuBarSelectionChanged = { [weak self] icon, included in self?.changeMembership(icon, included: included) }
        model.menuBarPresentationChanged = { [weak self] _ in
            self?.updateDividers()
            self?.queueShelfPresentation()
        }

        Publishers.MergeMany([
            model.$preferences.map { _ in () }.eraseToAnyPublisher(),
            model.$isSleeping.map { _ in () }.eraseToAnyPublisher()
        ])
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.refresh() }
        .store(in: &subscriptions)
        model.$snapshot.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.updateStatusText()
            self?.updateAnimation()
        }.store(in: &subscriptions)
        refresh()
    }

    func shutDown() {
        closePopover()
        animationTimer?.invalidate()
        presentationTask?.cancel()
        shelf.close()
        fixtureItems.forEach(NSStatusBar.system.removeStatusItem)
        fixtureItems = []
        unregisterShortcut()
        // Collapse the spacers before removing them so other apps’ icons return immediately.
        removeDividers()
        NSStatusBar.system.removeStatusItem(item)
    }

    func closePopover() {
        popover.performClose(nil)
        model.isPopoverVisible = false
        model.closeIconShelf()
        shelf.close()
    }

    func popoverDidClose(_ notification: Notification) { model.isPopoverVisible = false }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else if model.preferences.menuBarEnabled && NSApp.currentEvent?.modifierFlags.contains(.shift) != true {
            popover.performClose(nil)
            model.isPopoverVisible = false
            model.toggleHidden()
        } else if popover.isShown {
            closePopover()
        } else if let button = item.button {
            model.closeIconShelf()
            shelf.close()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            model.isPopoverVisible = true
            Task { await model.refreshPorts() }
        }
    }

    @objc private func dividerClicked() {
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true { model.revealAll() }
        else { model.toggleHidden() }
    }

    @objc private func dashboardClicked() { model.openDashboard?(.overview) }
    @objc private func settingsClicked() { model.openDashboard?(.settings) }
    @objc private func revealClicked() { model.revealAll() }
    @objc private func monitorClicked() {
        model.closeIconShelf()
        shelf.close()
        guard let button = item.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        model.isPopoverVisible = true
    }
    @objc private func quitClicked() { NSApp.terminate(nil) }

    private func showContextMenu() {
        let menu = NSMenu()
        let dashboard = menu.addItem(withTitle: "Open Dashboard", action: #selector(dashboardClicked), keyEquivalent: "")
        dashboard.target = self
        let monitor = menu.addItem(withTitle: "Quick Monitor", action: #selector(monitorClicked), keyEquivalent: "")
        monitor.target = self
        if model.preferences.menuBarEnabled {
            let reveal = menu.addItem(withTitle: "Open All Hidden Icons", action: #selector(revealClicked), keyEquivalent: "")
            reveal.target = self
        }
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(settingsClicked), keyEquivalent: ",")
        settings.target = self
        let quit = menu.addItem(withTitle: "Quit Barloom", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    private func refresh() {
        updateDividers()
        updateStatusText()
        updateAnimation()
        queueShelfPresentation()
    }

    private func makeDivider(name: String, symbol: String, tooltip: String) -> NSStatusItem {
        let divider = NSStatusBar.system.statusItem(withLength: 18)
        divider.autosaveName = name
        divider.isVisible = true
        if let button = divider.button {
            button.image = nil
            button.title = ""
            button.isEnabled = false
            button.setAccessibilityElement(false)
        }
        return divider
    }

    private func updateDividers() {
        guard model.preferences.menuBarEnabled else {
            removeDividers()
            unregisterShortcut()
            presentationTask?.cancel()
            shelf.close()
            return
        }
        if hiddenDivider == nil {
            hiddenDivider = makeDivider(name: "\(namespace).hidden", symbol: "chevron.compact.down", tooltip: "Open hidden icons below the menu bar")
            registerShortcut()
        }
        if let divider = alwaysDivider {
            divider.length = 18
            NSStatusBar.system.removeStatusItem(divider)
            alwaysDivider = nil
        }
        let width = MenuBarGeometry.collapsedSpacerLength
        let length: CGFloat = model.isArrangingMenuBar ? 18 : width
        if hiddenDivider?.length != length { hiddenDivider?.length = length }
        if alwaysDivider?.length != length { alwaysDivider?.length = length }
    }

    private func isLeftOfControl(_ divider: NSStatusItem?) -> Bool {
        guard let dividerWindow = divider?.button?.window, let controlWindow = item.button?.window else { return false }
        return dividerWindow.frame.maxX <= controlWindow.frame.minX + 2
    }

    private func isLeftOfHiddenDivider(_ divider: NSStatusItem?) -> Bool {
        guard let dividerWindow = divider?.button?.window, let hiddenWindow = hiddenDivider?.button?.window else { return false }
        // Compare right edges: the hidden spacer may already span beyond the left screen edge.
        return dividerWindow.frame.maxX < hiddenWindow.frame.maxX
    }

    private func removeDividers() {
        for divider in [alwaysDivider, hiddenDivider].compactMap({ $0 }) {
            divider.length = 18
            NSStatusBar.system.removeStatusItem(divider)
        }
        hiddenDivider = nil
        alwaysDivider = nil
    }

    private func updateStatusText() {
        guard let button = item.button else { return }
        let text: String
        if !model.preferences.statsEnabled {
            text = ""
        } else {
            switch model.preferences.statusMetric {
            case .none: text = ""
            case .cpu: text = MetricFormat.percent(model.snapshot?.cpuUsage)
            case .memory: text = MetricFormat.percent(model.snapshot?.memory?.usagePercent)
            case .network: text = "↓ " + MetricFormat.rate(model.snapshot?.network?.receivedBytesPerSecond)
            }
        }
        button.attributedTitle = NSAttributedString(string: text.isEmpty ? "" : " " + text, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)])
        button.imagePosition = .imageLeft
        button.toolTip = "Barloom · CPU \(MetricFormat.percent(model.snapshot?.cpuUsage)) · Memory \(MetricFormat.percent(model.snapshot?.memory?.usagePercent))"
    }

    private func updateAnimation() {
        if model.preferences.customMenuBarIcon, let image = model.customMenuBarImage {
            animationTimer?.invalidate()
            animationTimer = nil
            animationRate = -1
            image.isTemplate = model.preferences.customIconTemplate
            item.button?.image = image
            return
        }
        guard model.preferences.runnerEnabled, !model.isSleeping else {
            animationTimer?.invalidate()
            animationTimer = nil
            animationRate = -1
            item.button?.image = StatusArtwork.brandImage()
            return
        }
        if character != model.preferences.runnerCharacter {
            character = model.preferences.runnerCharacter
            frames = StatusArtwork.frames(for: model.preferences.runnerCharacter)
            frame = 0
        }
        let rate = AnimationCadence.framesPerSecond(cpuUsage: model.snapshot?.cpuUsage,
                                                  reducedMotion: model.preferences.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        guard rate != animationRate else { return }
        animationRate = rate
        animationTimer?.invalidate()
        animationTimer = nil
        drawNextFrame()
        guard rate > 0 else { return }
        let timer = Timer(timeInterval: 1 / rate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.drawNextFrame() }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func drawNextFrame() {
        guard !frames.isEmpty else { return }
        item.button?.image = frames[frame % frames.count]
        frame = (frame + 1) % frames.count
    }

    private func queueShelfPresentation() {
        presentationTask?.cancel()
        guard let section = model.overflowSection, model.preferences.menuBarEnabled, !model.isSleeping, !model.isArrangingMenuBar else {
            shelf.close()
            return
        }
        presentationTask = Task { [weak self] in
            guard let self, let context = await self.makeShelfContext(), !Task.isCancelled,
                  self.model.overflowSection == section else { return }
            self.shelf.show(section: section, context: context)
        }
    }

    private func makeShelfContext() async -> IconShelfContext? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first else { return nil }
        if model.preferences.menuBarSelectionConfigured { await model.menuBarLibrary.refresh(on: screen) }
        let top = MenuBarDisplay.primaryDisplayTop
        let windows = await MenuBarCatalog().windows()
        let rowTop = MenuBarDisplay.statusRowTop(on: screen, windows: windows, primaryDisplayTop: top)
        let row = windows.filter { abs($0.frame.minY - rowTop) < 8 }
        let nativeNumber = item.button?.window?.windowNumber ?? 0
        let expectedWidth = max(26, item.button?.window?.frame.width ?? 26)
        let control = row.first { $0.title == "\(namespace).control" } ?? row.first {
            $0.id == (UInt32(exactly: nativeNumber) ?? 0) && $0.isIconSized
        } ?? row.first {
            $0.title == Bundle.main.bundleIdentifier && $0.isIconSized &&
            $0.frame.midX >= screen.frame.minX && $0.frame.midX < screen.frame.maxX &&
            abs($0.frame.width - expectedWidth) < 20
        }
        let hidden = row.first { $0.title == "\(namespace).hidden" } ?? row.filter {
            $0.frame.width > 1_000 && ($0.title == Bundle.main.bundleIdentifier || $0.title.hasPrefix("Barloom.")) &&
            $0.frame.maxX <= (control?.frame.minX ?? screen.frame.maxX) + 2
        }.max { $0.frame.maxX < $1.frame.maxX }
        let anchor = control.map { MenuBarGeometry.quartzRect(fromAppKit: $0.frame, primaryDisplayTop: top) } ??
            CGRect(x: min(screen.frame.maxX - 40, max(screen.frame.minX + 20, NSEvent.mouseLocation.x)),
                   y: screen.frame.maxY - NSStatusBar.system.thickness, width: 30, height: NSStatusBar.system.thickness)
        return IconShelfContext(screen: screen, anchorFrame: anchor, primaryDisplayTop: top,
                                controlWindowID: control?.id ?? 0, hiddenWindowID: hidden?.id ?? 0,
                                alwaysWindowID: nil, sourceControlWidth: control?.frame.width ?? expectedWidth,
                                fixtureIcons: fixtureSnapshots(primaryDisplayTop: top), fixtureAction: fixtureItems.isEmpty ? nil : { [weak self] id in self?.fixtureActivated(id) },
                                selectedWindowIDs: model.preferences.menuBarSelectionConfigured && model.overflowSection != .all ?
                                    Set(model.menuBarLibrary.icons.filter { model.preferences.selectedMenuBarItems.contains($0.key) }.map(\.id)) : nil)
    }

    private func changeMembership(_ icon: LibraryMenuBarIcon, included: Bool) {
        model.closeIconShelf()
        // Selection controls the lower bar even when macOS refuses to rearrange an item.
        // An unselected hidden item stays available through Open All Hidden Icons.
        guard included, !model.menuBarLibrary.defaultHiddenKeys.contains(icon.key) else { return }
        Task { [weak self] in
            guard let self, let context = await self.makeShelfContext() else { return }
            let windows = await MenuBarCatalog().windows()
            let source = windows.first { $0.id == icon.id }
            let anchor = windows.first { $0.id == context.hiddenWindowID || $0.title == "\(self.namespace).hidden" }
            guard let source, let anchor else { self.model.menuBarLibrary.notice = "Refresh the icons before changing this selection."; return }
            do {
                try await MenuBarActivation().move(source, nextTo: anchor, before: included)
                await self.model.menuBarLibrary.refresh()
            } catch {
                self.model.menuBarLibrary.notice = "Selected for Barloom, but macOS kept the original icon in place. \(error.localizedDescription)"
            }
        }
    }

    func installSmokeFixtures() {
        let symbols = ["wifi", "bolt.fill", "cloud", "headphones", "terminal", "lock", "paperplane", "star", "moon", "sun.max", "camera", "bell", "gear", "network", "cpu", "leaf"]
        for (index, symbol) in symbols.enumerated() {
            let fixture = NSStatusBar.system.statusItem(withLength: 26)
            fixture.autosaveName = "Barloom.ShelfSmoke.fixture.\(index)"
            fixture.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Test \(symbol)")
            fixture.button?.target = self
            fixture.button?.action = #selector(fixtureButtonClicked)
            fixtureItems.append(fixture)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            model.revealAll()
        }
    }

    private func fixtureSnapshots(primaryDisplayTop: CGFloat) -> [CapturedMenuBarIcon] {
        fixtureItems.enumerated().compactMap { index, item in
            guard let button = item.button,
                  let bitmap = button.bitmapImageRepForCachingDisplay(in: button.bounds) else { return nil }
            button.cacheDisplay(in: button.bounds, to: bitmap)
            let record = MenuBarWindow(id: UInt32(index + 1), ownerPID: getpid(), ownerName: "Barloom Test",
                                       title: "Test icon \(index + 1)", frame: CGRect(x: CGFloat(index) * 30, y: 0, width: 30, height: 30))
            return CapturedMenuBarIcon(window: record, png: bitmap.representation(using: .png, properties: [:]))
        }
    }

    private func fixtureActivated(_ id: UInt32) {
        guard id > 0, Int(id) <= fixtureItems.count else { return }
        let fixture = fixtureItems[Int(id) - 1]
        fixture.button?.performClick(nil)
    }

    @objc private func fixtureButtonClicked() {
        let alert = NSAlert()
        alert.messageText = "Test icon opened"
        alert.informativeText = "The icon bar closed and activated a real status item. The hidden section stayed collapsed."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func registerShortcut() {
        guard hotKey == nil else { return }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<MenuBarController>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { controller.model.toggleHidden() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        guard installed == noErr else { model.shortcutAvailable = false; return }
        let id = EventHotKeyID(signature: 0x424C4F4D, id: 1)
        let registered = RegisterEventHotKey(UInt32(kVK_ANSI_B), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
        model.shortcutAvailable = registered == noErr
    }

    private func unregisterShortcut() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        hotKey = nil
        hotKeyHandler = nil
        model.shortcutAvailable = false
    }
}
