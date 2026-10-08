import AppKit
import BarloomCore
import Combine
import Foundation

enum DashboardPage: String, CaseIterable, Identifiable {
    case overview, menuBar, system, runner, ports, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .menuBar: "Menu Bar"
        case .system: "System Monitor"
        case .runner: "Runner"
        case .ports: "Local Ports"
        case .settings: "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .menuBar: "menubar.rectangle"
        case .system: "waveform.path.ecg"
        case .runner: "cat"
        case .ports: "network"
        case .settings: "slider.horizontal.3"
        }
    }
    var subtitle: String {
        switch self {
        case .overview: "Your Mac. One bar. Everything."
        case .menuBar: "A little less clutter. A little more room."
        case .system: "Know what your Mac is doing, as it happens."
        case .runner: "A small companion with a feel for your CPU."
        case .ports: "Find what’s listening on localhost."
        case .settings: "Make Barloom feel like yours."
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var preferences: Preferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: "preferences.v1") }
            if !preferences.menuBarEnabled {
                overflowSection = nil
                isArrangingMenuBar = false
            }
            if started { reconcileServices() }
        }
    }
    @Published private(set) var snapshot: SystemSnapshot?
    @Published private(set) var history: [HistorySample] = []
    @Published private(set) var ports: [ListeningPort] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastPortScan: Date?
    @Published var portError: String?
    @Published var stoppingPID: Int32?
    @Published var selectedPage: DashboardPage = .overview
    @Published var overflowSection: MenuBarSection? {
        didSet { menuBarPresentationChanged?(overflowSection) }
    }
    @Published var isArrangingMenuBar = false
    @Published var menuBarNotice: String?
    @Published var shortcutAvailable = false
    @Published var isDashboardVisible = false
    @Published var isPopoverVisible = false
    @Published var isSleeping = false
    @Published var customMenuBarImage: NSImage?
    let menuBarAccess = MenuBarAccess()
    let menuBarLibrary = MenuBarLibrary()
    var menuBarSelectionChanged: ((LibraryMenuBarIcon, Bool) -> Void)?
    var menuBarPresentationChanged: ((MenuBarSection?) -> Void)?

    var openDashboard: ((DashboardPage) -> Void)?
    private let defaults: UserDefaults
    private let monitor = SystemMonitor()
    private let scanner = PortScanner()
    private var samplerTask: Task<Void, Never>?
    private var portTask: Task<Void, Never>?
    private var samplingConfiguration: String?
    private var started = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "preferences.v1"), let saved = try? JSONDecoder().decode(Preferences.self, from: data) {
            preferences = saved
        } else {
            preferences = Preferences()
        }
        customMenuBarImage = preferences.customMenuBarIcon ? CustomMenuBarIcon.load(template: preferences.customIconTemplate) : nil
    }

    func chooseMenuBarIcon() {
        do {
            guard let image = try CustomMenuBarIcon.choose() else { return }
            customMenuBarImage = image
            preferences.customMenuBarIcon = true
            preferences.customIconTemplate = false
        } catch {
            menuBarNotice = "Could not import this image. Choose a supported image smaller than 20 MB."
        }
    }

    func resetMenuBarIcon() {
        preferences.customMenuBarIcon = false
        customMenuBarImage = nil
    }

    func setMenuBarIcon(_ icon: LibraryMenuBarIcon, included: Bool) {
        if !preferences.menuBarSelectionConfigured {
            preferences.selectedMenuBarItems = Array(menuBarLibrary.defaultHiddenKeys).sorted()
        }
        preferences.menuBarSelectionConfigured = true
        if included {
            if !preferences.selectedMenuBarItems.contains(icon.key) { preferences.selectedMenuBarItems.append(icon.key) }
        } else { preferences.selectedMenuBarItems.removeAll { $0 == icon.key } }
        menuBarSelectionChanged?(icon, included)
    }

    func isMenuBarIconIncluded(_ icon: LibraryMenuBarIcon) -> Bool {
        preferences.menuBarSelectionConfigured ? preferences.selectedMenuBarItems.contains(icon.key) :
            menuBarLibrary.defaultHiddenKeys.contains(icon.key)
    }

    var activeModuleCount: Int {
        [preferences.menuBarEnabled, preferences.statsEnabled, preferences.runnerEnabled, preferences.portsEnabled].filter { $0 }.count
    }

    var sharedPorts: Set<Int> {
        Set(Dictionary(grouping: ports, by: \.port).filter { Set($0.value.map(\.pid)).count > 1 }.keys)
    }

    func start() {
        started = true
        reconcileServices()
    }

    func stop() {
        started = false
        samplerTask?.cancel()
        samplerTask = nil
        portTask?.cancel()
        portTask = nil
    }

    func setSleeping(_ sleeping: Bool) {
        isSleeping = sleeping
        reconcileServices()
    }

    func toggleHidden() {
        guard preferences.menuBarEnabled else { return }
        isArrangingMenuBar = false
        overflowSection = overflowSection == .hidden ? nil : .hidden
    }

    func revealAll() {
        guard preferences.menuBarEnabled else { return }
        isArrangingMenuBar = false
        overflowSection = .all
    }

    func toggleAlwaysHidden() {
        guard preferences.menuBarEnabled, preferences.alwaysHiddenEnabled else { return }
        isArrangingMenuBar = false
        overflowSection = overflowSection == .alwaysHidden ? nil : .alwaysHidden
    }

    func closeIconShelf() { overflowSection = nil }

    func toggleMenuBarArrangement() {
        overflowSection = nil
        isArrangingMenuBar.toggle()
        if !isArrangingMenuBar { menuBarNotice = nil }
    }

    func refreshPorts() async {
        guard preferences.portsEnabled, !isScanning, !isSleeping else { return }
        isScanning = true
        defer { isScanning = false }
        do {
            let result = try await scanner.scan()
            guard !Task.isCancelled, preferences.portsEnabled, !isSleeping else { return }
            ports = result
            portError = nil
            lastPortScan = Date()
        } catch is CancellationError {
            return
        } catch {
            guard preferences.portsEnabled else { return }
            portError = error.localizedDescription
        }
    }

    func canStop(_ port: ListeningPort) -> Bool {
        TerminationPolicy.canStop(port.identity, currentUserID: getuid(), ownPID: getpid())
    }

    func stopProcess(_ port: ListeningPort) async {
        guard stoppingPID == nil else { return }
        stoppingPID = port.pid
        defer { stoppingPID = nil }
        do {
            try await scanner.stop(port)
            try await Task.sleep(for: .milliseconds(600))
            await refreshPorts()
        } catch {
            portError = error.localizedDescription
        }
    }

    func openPort(_ port: ListeningPort) {
        guard let url = port.localURL else { return }
        NSWorkspace.shared.open(url)
    }

    func copyURL(_ port: ListeningPort) {
        guard let url = port.localURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    private func reconcileServices() {
        let shouldSample = !isSleeping && (preferences.statsEnabled || preferences.runnerEnabled)
        let key = shouldSample ? "\(preferences.refreshInterval.rawValue)-\(preferences.statsEnabled)" : nil
        if key != samplingConfiguration {
            samplerTask?.cancel()
            samplerTask = nil
            samplingConfiguration = key
            if shouldSample {
                samplerTask = Task { [weak self, monitor] in
                    await monitor.resetBaselines()
                    while !Task.isCancelled {
                        guard let self else { return }
                        let next = await monitor.sample(includeDetails: self.preferences.statsEnabled)
                        guard !Task.isCancelled else { return }
                        self.snapshot = next
                        if self.preferences.statsEnabled {
                            self.history.append(HistorySample(snapshot: next))
                            if self.history.count > 90 { self.history.removeFirst(self.history.count - 90) }
                        }
                        do { try await Task.sleep(for: .seconds(self.preferences.refreshInterval.rawValue)) }
                        catch { return }
                    }
                }
            } else {
                snapshot = nil
            }
        }
        if !preferences.statsEnabled { history.removeAll(keepingCapacity: true) }

        let shouldScan = !isSleeping && preferences.portsEnabled
        if shouldScan && portTask == nil {
            portTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    await self.refreshPorts()
                    do { try await Task.sleep(for: .seconds(self.isDashboardVisible || self.isPopoverVisible ? 5 : 20)) }
                    catch { return }
                }
            }
        } else if !shouldScan {
            portTask?.cancel()
            portTask = nil
            ports = []
            lastPortScan = nil
            portError = nil
        }
    }
}
