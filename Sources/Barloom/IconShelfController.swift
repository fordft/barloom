import AppKit
import BarloomCore
import Combine
import SwiftUI

struct IconShelfContext {
    let screen: NSScreen
    let anchorFrame: CGRect
    let primaryDisplayTop: CGFloat
    let controlWindowID: UInt32
    let hiddenWindowID: UInt32
    let alwaysWindowID: UInt32?
    let sourceControlWidth: CGFloat
    let fixtureIcons: [CapturedMenuBarIcon]
    let fixtureAction: ((UInt32) -> Void)?
    let selectedWindowIDs: Set<UInt32>?
}

@MainActor
final class IconShelfState: ObservableObject {
    @Published var icons: [CapturedMenuBarIcon] = []
    @Published var isLoading = false
    @Published var canCapture = false
    @Published var canControl = false
    @Published var notice: String?
    @Published var section: MenuBarSection = .hidden
    @Published var width: CGFloat = 480
}

@MainActor
final class IconShelfPanel: NSPanel {
    var dismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { dismiss?() }
}

@MainActor
final class IconShelfController {
    private let model: AppModel
    private let state = IconShelfState()
    private let catalog = MenuBarCatalog()
    private let activation = MenuBarActivation()
    private let panel: IconShelfPanel
    private var context: IconShelfContext?
    private var refreshTask: Task<Void, Never>?
    private var autoCloseTask: Task<Void, Never>?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var observations: Set<AnyCancellable> = []

    var isVisible: Bool { panel.isVisible }
    var frame: CGRect { panel.frame }

    init(model: AppModel) {
        self.model = model
        panel = IconShelfPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 52), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Barloom Icon Bar"
        panel.isFloatingPanel = true
        panel.level = .mainMenu + 1
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace, .ignoresCycle]
        panel.allowsToolTipsWhenApplicationIsInactive = true

        let background = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 480, height: 52))
        background.material = .menu
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 13
        background.layer?.masksToBounds = true
        let view = NSHostingView(rootView: IconShelfView(state: state, openSettings: { [weak model] in
            model?.openDashboard?(.menuBar)
        }, close: { [weak model] in
            model?.closeIconShelf()
        }, activate: { [weak self] icon, right in
            self?.activate(icon, rightClick: right)
        }))
        view.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            view.topAnchor.constraint(equalTo: background.topAnchor),
            view.bottomAnchor.constraint(equalTo: background.bottomAnchor)
        ])
        panel.contentView = background
        panel.dismiss = { [weak model] in model?.closeIconShelf() }

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main).sink { [weak model] _ in model?.closeIconShelf() }.store(in: &observations)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: RunLoop.main).sink { [weak model] _ in model?.closeIconShelf() }.store(in: &observations)
    }

    func show(section: MenuBarSection, context: IconShelfContext) {
        close()
        self.context = context
        state.section = section
        state.icons = []
        state.notice = nil
        state.isLoading = true
        model.menuBarAccess.refresh()
        state.canCapture = model.menuBarAccess.canCapture || !context.fixtureIcons.isEmpty
        state.canControl = model.menuBarAccess.canControl || context.fixtureAction != nil
        resize(width: 480)
        panel.orderFrontRegardless()
        panel.makeKey()
        resize(width: 480)
        installDismissMonitors()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshIcons()
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
            }
        }
        if model.preferences.autoHideSeconds > 0 {
            autoCloseTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await Task.sleep(for: .seconds(self.model.preferences.autoHideSeconds))
                    while self.panel.frame.contains(NSEvent.mouseLocation) {
                        try await Task.sleep(for: .milliseconds(300))
                    }
                    self.model.closeIconShelf()
                } catch { return }
            }
        }
    }

    func close() {
        refreshTask?.cancel()
        refreshTask = nil
        autoCloseTask?.cancel()
        autoCloseTask = nil
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        panel.orderOut(nil)
        context = nil
        state.icons = []
    }

    private func refreshIcons() async {
        guard let context, panel.isVisible else { return }
        defer { state.isLoading = false }
        if !context.fixtureIcons.isEmpty {
            state.icons = context.fixtureIcons
            resizeToIcons()
            return
        }
        model.menuBarAccess.refresh()
        state.canCapture = model.menuBarAccess.canCapture
        state.canControl = model.menuBarAccess.canControl
        guard state.canCapture else { state.icons = []; resize(width: 540); return }
        let windows = await catalog.windows()
        guard !Task.isCancelled else { return }
        let rowTop = MenuBarDisplay.statusRowTop(on: context.screen, windows: windows, primaryDisplayTop: context.primaryDisplayTop)
        let row = windows.filter { abs($0.frame.minY - rowTop) < 8 && (12...48).contains($0.frame.height) }
        let identifier = Bundle.main.bundleIdentifier ?? "com.barloom.app"
        func isOwn(_ window: MenuBarWindow) -> Bool {
            window.ownerPID == getpid() || window.title == identifier || window.title.hasPrefix("Barloom.")
        }
        let own = row.filter(isOwn)
        let control = own.first { $0.id == context.controlWindowID && context.screen.frame.minX <= $0.frame.midX && $0.frame.midX < context.screen.frame.maxX } ?? own.first {
            context.screen.frame.minX <= $0.frame.midX && $0.frame.midX < context.screen.frame.maxX &&
            abs($0.frame.width - context.sourceControlWidth) < 4
        }
        guard let control else {
            state.notice = "Could not locate Barloom on this display. Close the bar and try again."
            state.icons = []
            resize(width: 560)
            return
        }
        let spacers = own.filter { $0.frame.width >= 1_000 }
        let hidden = spacers.first { $0.id == context.hiddenWindowID && abs($0.frame.maxX - control.frame.minX) < 240 } ?? spacers.filter {
            $0.frame.maxX <= control.frame.minX + 2
        }.max { $0.frame.maxX < $1.frame.maxX }
        guard let hidden else {
            state.notice = "Finish Arrange mode to display hidden icons in this bar."
            state.icons = []
            resize(width: 520)
            return
        }
        // Every normal hidden spacer ends next to an onscreen control. Always-hidden
        // spacers end far offscreen, to the left of those normal hidden spacers.
        let hiddenSpacers = spacers.filter { candidate in
            row.contains { other in isOwn(other) && other.isIconSized && abs(other.frame.minX - candidate.frame.maxX) < 200 }
        }
        let hiddenIDs = Set(hiddenSpacers.map(\.id)).union([hidden.id])
        let dividers = spacers.map { MenuBarDivider(windowID: $0.id, frame: $0.frame, section: hiddenIDs.contains($0.id) ? .hidden : .alwaysHidden) }
        let selected: [MenuBarWindow]
        if let ids = context.selectedWindowIDs {
            selected = row.filter { ids.contains($0.id) && $0.isIconSized }.sorted { $0.frame.minX < $1.frame.minX }
        } else {
            selected = MenuBarGeometry.icons(row, between: dividers, selectedDividerID: hidden.id,
                                            section: state.section, excludedIDs: Set(own.map(\.id)))
        }
        let captured = await catalog.capture(selected)
        guard !Task.isCancelled else { return }
        state.icons = captured
        state.notice = captured.contains(where: { $0.png == nil }) ? "Some icons could not be captured. Refresh the bar to try again." : nil
        resizeToIcons()
    }

    private func resizeToIcons() {
        let total = state.icons.reduce(CGFloat(0)) { sum, icon in sum + max(32, min(160, icon.window.frame.width)) + 4 }
        resize(width: state.icons.isEmpty ? 380 : total + 100)
    }

    private func resize(width: CGFloat) {
        guard let context else { return }
        let screen = context.screen
        let barHeight = max(NSStatusBar.system.thickness, screen.frame.maxY - screen.visibleFrame.maxY)
        let target = MenuBarGeometry.shelfFrame(screen: screen.frame, menuBarHeight: barHeight,
                                                notchHeight: screen.safeAreaInsets.top, anchorX: context.anchorFrame.maxX, desiredWidth: width)
        state.width = target.width
        panel.setFrame(target, display: true)
    }

    private func activate(_ icon: CapturedMenuBarIcon, rightClick: Bool) {
        if let action = context?.fixtureAction {
            model.closeIconShelf()
            action(icon.id)
            return
        }
        guard state.canControl else { model.openDashboard?(.menuBar); return }
        model.closeIconShelf()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(60))
                try await self.activation.activate(icon.window, rightClick: rightClick)
            } catch {
                self.model.menuBarNotice = error.localizedDescription
                self.model.openDashboard?(.menuBar)
            }
        }
    }

    private func installDismissMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissIfOutside() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.dismissIfOutside() }
            return event
        }
    }

    private func dismissIfOutside() {
        guard panel.isVisible, let context else { return }
        let location = NSEvent.mouseLocation
        if !panel.frame.contains(location) && !context.anchorFrame.insetBy(dx: -8, dy: -3).contains(location) {
            model.closeIconShelf()
        }
    }
}

struct IconShelfView: View {
    @ObservedObject var state: IconShelfState
    let openSettings: () -> Void
    let close: () -> Void
    let activate: (CapturedMenuBarIcon, Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if !state.canCapture {
                Image(systemName: "lock.rectangle").foregroundStyle(AppColors.violet)
                Text("Allow Screen Recording to show hidden icons.").font(.system(size: 12)).lineLimit(1)
                Spacer(minLength: 4)
                Button("Allow access…", action: openSettings).controlSize(.small)
            } else if state.isLoading && state.icons.isEmpty {
                ProgressView().controlSize(.small)
                Text("Loading hidden icons…").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
            } else if state.icons.isEmpty {
                Image(systemName: "menubar.rectangle").foregroundStyle(AppColors.violet)
                Text(state.notice ?? "No icons selected. Choose them in Menu Bar settings.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(state.icons) { icon in
                            MenuBarIconButton(icon: icon, activate: { right in activate(icon, right) })
                                .frame(width: max(32, min(160, icon.window.frame.width)), height: 36)
                                .help(icon.window.title.isEmpty ? icon.window.ownerName : icon.window.title)
                        }
                    }
                }.scrollIndicators(.hidden)
                if !state.canControl {
                    Button(action: openSettings) { Image(systemName: "hand.tap") }.help("Allow Accessibility to click icons")
                }
            }
            Divider().frame(height: 22)
            Button(action: openSettings) { Image(systemName: "slider.horizontal.3") }.help("Menu Bar settings")
            Button(action: close) { Image(systemName: "xmark") }.help("Close icon bar · Escape")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .frame(width: state.width, height: 52)
        .accessibilityLabel(state.section.title)
    }
}

struct MenuBarIconButton: NSViewRepresentable {
    let icon: CapturedMenuBarIcon
    let activate: (Bool) -> Void

    @MainActor
    static func image(for icon: CapturedMenuBarIcon) -> NSImage? {
        guard let png = icon.png, let image = NSImage(data: png) else { return nil }
        // Quartz returns backing pixels at the display's scale. NSImage(data:)
        // treats those pixels as points, so Retina captures otherwise render
        // twice as large and get needlessly scaled down by NSButton.
        let logicalSize = icon.window.frame.size
        let scale = min(1, 24 / max(1, logicalSize.height))
        image.size = CGSize(width: logicalSize.width * scale, height: logicalSize.height * scale)
        return image
    }

    @MainActor
    final class IconButton: NSButton {
        var activate: ((Bool) -> Void)?
        override func rightMouseDown(with event: NSEvent) {}
        override func rightMouseUp(with event: NSEvent) { activate?(true) }
        @objc func clicked() { activate?(NSApp.currentEvent?.modifierFlags.contains(.control) == true) }
    }

    func makeNSView(context: Context) -> IconButton {
        let button = IconButton()
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .regularSquare
        button.target = button
        button.action = #selector(IconButton.clicked)
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: IconButton, context: Context) {
        button.activate = activate
        button.setAccessibilityLabel(icon.window.title.isEmpty ? icon.window.ownerName : icon.window.title)
        button.image = Self.image(for: icon) ?? NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: "Icon unavailable")
        button.isEnabled = icon.png != nil
    }
}
