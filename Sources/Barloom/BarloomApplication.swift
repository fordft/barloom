import AppKit
import BarloomCore
import Foundation
import SwiftUI

@main
enum BarloomApplication {
    @MainActor
    static func main() async {
        if CommandLine.arguments.contains("--diagnostics") {
            await diagnostics()
            return
        }
        let application = NSApplication.shared
        if let identifier = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { $0.processIdentifier != getpid() }) {
            existing.activate()
            return
        }
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }

    private static func diagnostics() async {
        struct Report: Encodable {
            let system: SystemSnapshot
            let ports: [ListeningPort]
            let portError: String?
        }
        let monitor = SystemMonitor()
        _ = await monitor.sample()
        try? await Task.sleep(for: .milliseconds(500))
        let snapshot = await monitor.sample()
        var ports: [ListeningPort] = []
        var portError: String?
        do { ports = try await PortScanner().scan() }
        catch { portError = error.localizedDescription }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(Report(system: snapshot, ports: ports, portError: portError)) {
            print(String(decoding: data, as: UTF8.self))
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private let model: AppModel = {
        if CommandLine.arguments.contains("--shelf-smoke-test"), let defaults = UserDefaults(suiteName: "com.barloom.app.shelfSmoke") {
            defaults.removePersistentDomain(forName: "com.barloom.app.shelfSmoke")
            return AppModel(defaults: defaults)
        }
        return AppModel()
    }()
    private var menuBar: MenuBarController?
    private var window: NSWindow?
    private var workspaceObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        model.openDashboard = { [weak self] page in self?.showDashboard(page: page) }
        if CommandLine.arguments.contains("--shelf-smoke-test") {
            model.preferences.menuBarEnabled = true
            model.preferences.statsEnabled = false
            model.preferences.runnerEnabled = false
            model.preferences.portsEnabled = false
        }
        menuBar = MenuBarController(model: model)
        if CommandLine.arguments.contains("--shelf-smoke-test") { menuBar?.installSmokeFixtures() }
        model.start()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.setSleeping(true) }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.setSleeping(false) }
        })
        if CommandLine.arguments.contains("--shelf-smoke-test") { return }
        if !UserDefaults.standard.bool(forKey: "hasLaunched.v1") || CommandLine.arguments.contains("--show-dashboard") || CommandLine.arguments.contains("--show-menu-bar-settings") {
            showDashboard(page: CommandLine.arguments.contains("--show-menu-bar-settings") ? .menuBar : .overview)
            UserDefaults.standard.set(true, forKey: "hasLaunched.v1")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBar?.shutDown()
        model.stop()
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard(page: model.selectedPage)
        return true
    }

    func windowWillClose(_ notification: Notification) {
        model.isDashboardVisible = false
        model.isArrangingMenuBar = false
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleHiddenItems) { return model.preferences.menuBarEnabled }
        return true
    }

    private func showDashboard(page: DashboardPage) {
        menuBar?.closePopover()
        model.selectedPage = page
        if window == nil {
            let newWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_040, height: 740),
                                     styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            newWindow.title = "Barloom"
            newWindow.titlebarAppearsTransparent = true
            newWindow.minSize = NSSize(width: 860, height: 620)
            newWindow.isReleasedWhenClosed = false
            newWindow.setFrameAutosaveName("Barloom.dashboard")
            newWindow.contentView = NSHostingView(rootView: DashboardView().environmentObject(model))
            newWindow.delegate = self
            newWindow.center()
            window = newWindow
        }
        model.isDashboardVisible = true
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        Task { await model.refreshPorts() }
    }

    @objc private func openDashboard() { showDashboard(page: .overview) }
    @objc private func openSettings() { showDashboard(page: .settings) }
    @objc private func toggleHiddenItems() { model.toggleHidden() }

    private func configureMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Barloom")
        let dashboard = appMenu.addItem(withTitle: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: "d")
        dashboard.target = self
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        let toggle = appMenu.addItem(withTitle: "Toggle Hidden Icon Bar", action: #selector(toggleHiddenItems), keyEquivalent: "b")
        toggle.keyEquivalentModifierMask = [.control, .option]
        toggle.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Barloom", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }
}
