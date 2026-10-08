import Foundation

public struct CPUTicks: Equatable, Sendable {
    public let user: UInt64
    public let system: UInt64
    public let idle: UInt64
    public let nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    public func usage(since previous: CPUTicks?) -> Double? {
        guard let previous,
              user >= previous.user, system >= previous.system,
              idle >= previous.idle, nice >= previous.nice else { return nil }
        let busy = Double(user - previous.user) + Double(system - previous.system) + Double(nice - previous.nice)
        let total = busy + Double(idle - previous.idle)
        guard total > 0 else { return nil }
        return min(100, max(0, busy / total * 100))
    }
}

public struct MemoryMetrics: Codable, Equatable, Sendable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let cachedBytes: UInt64
    public let compressedBytes: UInt64
    public var usagePercent: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) * 100 : 0 }
}

public struct DiskMetrics: Codable, Equatable, Sendable {
    public let totalBytes: Int64
    public let availableBytes: Int64
    public var usagePercent: Double { totalBytes > 0 ? Double(totalBytes - availableBytes) / Double(totalBytes) * 100 : 0 }
}

public struct BatteryMetrics: Codable, Equatable, Sendable {
    public let percent: Int
    public let isCharging: Bool
    public let isPluggedIn: Bool
    public let minutesRemaining: Int?
}

public struct NetworkCounters: Equatable, Sendable {
    public let received: UInt64
    public let sent: UInt64
    public init(received: UInt64, sent: UInt64) {
        self.received = received
        self.sent = sent
    }
}

public struct NetworkMetrics: Codable, Equatable, Sendable {
    public let receivedBytesPerSecond: Double
    public let sentBytesPerSecond: Double

    public static func rates(
        current: [String: NetworkCounters], previous: [String: NetworkCounters], elapsed: Double
    ) -> NetworkMetrics? {
        guard elapsed.isFinite, elapsed > 0, !previous.isEmpty, !current.isEmpty else { return nil }
        var received: UInt64 = 0
        var sent: UInt64 = 0
        var matched = false
        for (name, counts) in current {
            guard let old = previous[name], counts.received >= old.received, counts.sent >= old.sent else { continue }
            matched = true
            received += counts.received - old.received
            sent += counts.sent - old.sent
        }
        guard matched else { return nil }
        return NetworkMetrics(receivedBytesPerSecond: Double(received) / elapsed, sentBytesPerSecond: Double(sent) / elapsed)
    }
}

public struct SystemSnapshot: Codable, Sendable {
    public let timestamp: Date
    public let cpuUsage: Double?
    public let memory: MemoryMetrics?
    public let disk: DiskMetrics?
    public let network: NetworkMetrics?
    public let battery: BatteryMetrics?
    public let uptimeSeconds: Double
    public let processorCount: Int
    public let thermalState: String
}

public struct HistorySample: Identifiable, Sendable {
    public let id: Date
    public let cpuUsage: Double?
    public let memoryUsage: Double?

    public init(snapshot: SystemSnapshot) {
        id = snapshot.timestamp
        cpuUsage = snapshot.cpuUsage
        memoryUsage = snapshot.memory?.usagePercent
    }
}

public enum MetricFormat {
    public static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    public static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .binary)
    }

    public static func rate(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        if value < 1_024 { return "\(Int(value)) B/s" }
        if value < 1_048_576 { return String(format: "%.0f KB/s", value / 1_024) }
        return String(format: "%.1f MB/s", value / 1_048_576)
    }

    public static func uptime(_ seconds: Double) -> String {
        let minutes = max(0, Int(seconds / 60))
        let days = minutes / 1_440
        let hours = minutes % 1_440 / 60
        return days > 0 ? "\(days)d \(hours)h" : "\(hours)h \(minutes % 60)m"
    }
}
