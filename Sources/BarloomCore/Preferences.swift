import Foundation

public enum StatusMetric: String, CaseIterable, Codable, Sendable, Identifiable {
    case none, cpu, memory, network
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .none: "Icon only"
        case .cpu: "CPU usage"
        case .memory: "Memory usage"
        case .network: "Download speed"
        }
    }
}

public enum RunnerCharacter: String, CaseIterable, Codable, Sendable, Identifiable {
    case cat, orbit, pulse
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum RefreshInterval: Int, CaseIterable, Codable, Sendable, Identifiable {
    case fast = 1, balanced = 2, relaxed = 5, quiet = 10
    public var id: Int { rawValue }
    public var title: String { "Every \(rawValue) \(rawValue == 1 ? "second" : "seconds")" }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var menuBarEnabled = false
    public var statsEnabled = true
    public var runnerEnabled = true
    public var portsEnabled = true
    public var alwaysHiddenEnabled = false
    public var autoHideSeconds = 0
    public var refreshInterval: RefreshInterval = .balanced
    public var statusMetric: StatusMetric = .cpu
    public var runnerCharacter: RunnerCharacter = .cat
    public var reduceMotion = false
    public var customMenuBarIcon = false
    public var customIconTemplate = false
    public var menuBarSelectionConfigured = false
    public var selectedMenuBarItems: [String] = []

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case menuBarEnabled, statsEnabled, runnerEnabled, portsEnabled
        case alwaysHiddenEnabled, autoHideSeconds, refreshInterval
        case statusMetric, runnerCharacter, reduceMotion
        case customMenuBarIcon, customIconTemplate
        case menuBarSelectionConfigured, selectedMenuBarItems
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        menuBarEnabled = try values.decodeIfPresent(Bool.self, forKey: .menuBarEnabled) ?? false
        statsEnabled = try values.decodeIfPresent(Bool.self, forKey: .statsEnabled) ?? true
        runnerEnabled = try values.decodeIfPresent(Bool.self, forKey: .runnerEnabled) ?? true
        portsEnabled = try values.decodeIfPresent(Bool.self, forKey: .portsEnabled) ?? true
        alwaysHiddenEnabled = try values.decodeIfPresent(Bool.self, forKey: .alwaysHiddenEnabled) ?? false
        let delay = try values.decodeIfPresent(Int.self, forKey: .autoHideSeconds) ?? 0
        autoHideSeconds = [0, 5, 10, 30].contains(delay) ? delay : 0
        refreshInterval = try values.decodeIfPresent(RefreshInterval.self, forKey: .refreshInterval) ?? .balanced
        statusMetric = try values.decodeIfPresent(StatusMetric.self, forKey: .statusMetric) ?? .cpu
        runnerCharacter = try values.decodeIfPresent(RunnerCharacter.self, forKey: .runnerCharacter) ?? .cat
        reduceMotion = try values.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? false
        customMenuBarIcon = try values.decodeIfPresent(Bool.self, forKey: .customMenuBarIcon) ?? false
        customIconTemplate = try values.decodeIfPresent(Bool.self, forKey: .customIconTemplate) ?? false
        menuBarSelectionConfigured = try values.decodeIfPresent(Bool.self, forKey: .menuBarSelectionConfigured) ?? false
        selectedMenuBarItems = try values.decodeIfPresent([String].self, forKey: .selectedMenuBarItems) ?? []
    }
}

public enum AnimationCadence {
    public static func framesPerSecond(cpuUsage: Double?, reducedMotion: Bool = false) -> Double {
        guard !reducedMotion else { return 0 }
        let usage = min(100, max(0, cpuUsage?.isFinite == true ? cpuUsage! : 0))
        // Keep the idle redraw rate low; AppKit mirrors status items to every display.
        return 2 + 6 * usage / 100
    }
}
