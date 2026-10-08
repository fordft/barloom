import Foundation
import Testing
@testable import BarloomCore

@Suite("Metric calculations")
struct MetricsTests {
    @Test func cpuUsesTickDeltasAndIncludesNiceTime() {
        let previous = CPUTicks(user: 100, system: 100, idle: 800, nice: 0)
        let current = CPUTicks(user: 120, system: 110, idle: 860, nice: 10)
        #expect(current.usage(since: previous) == 40)
    }

    @Test func cpuNeedsABaselineAndRejectsResetCounters() {
        let ticks = CPUTicks(user: 20, system: 10, idle: 70, nice: 0)
        #expect(ticks.usage(since: nil) == nil)
        #expect(ticks.usage(since: ticks) == nil)
        #expect(CPUTicks(user: 1, system: 1, idle: 1, nice: 0).usage(since: ticks) == nil)
    }

    @Test func networkDoesNotSpikeWhenAnInterfaceAppearsOrResets() throws {
        let previous = ["en0": NetworkCounters(received: 1_000, sent: 400)]
        let current = ["en0": NetworkCounters(received: 3_000, sent: 1_400), "en1": NetworkCounters(received: 900_000, sent: 800_000)]
        let rates = try #require(NetworkMetrics.rates(current: current, previous: previous, elapsed: 2))
        #expect(rates.receivedBytesPerSecond == 1_000)
        #expect(rates.sentBytesPerSecond == 500)
        #expect(NetworkMetrics.rates(current: ["en0": .init(received: 10, sent: 10)], previous: previous, elapsed: 2) == nil)
        #expect(NetworkMetrics.rates(current: current, previous: previous, elapsed: 0) == nil)
        #expect(NetworkMetrics.rates(current: current, previous: [:], elapsed: 2) == nil)
    }

    @Test func runnerCadenceIsBoundedAndRespectsReducedMotion() {
        #expect(AnimationCadence.framesPerSecond(cpuUsage: nil) == 2)
        #expect(AnimationCadence.framesPerSecond(cpuUsage: -.infinity) == 2)
        #expect(AnimationCadence.framesPerSecond(cpuUsage: .nan) == 2)
        #expect(AnimationCadence.framesPerSecond(cpuUsage: -10) == 2)
        #expect(AnimationCadence.framesPerSecond(cpuUsage: 200) == 8)
        #expect(AnimationCadence.framesPerSecond(cpuUsage: 25) == 3.5)
        #expect(AnimationCadence.framesPerSecond(cpuUsage: 70, reducedMotion: true) == 0)
    }

    @Test func networkCountsTrafficBeyondFourGigabytes() throws {
        let previous = ["en0": NetworkCounters(received: 4_294_967_000, sent: 8_000_000_000)]
        let current = ["en0": NetworkCounters(received: 4_294_969_000, sent: 8_000_001_000)]
        let rates = try #require(NetworkMetrics.rates(current: current, previous: previous, elapsed: 2))
        #expect(rates.receivedBytesPerSecond == 1_000)
        #expect(rates.sentBytesPerSecond == 500)
    }

    @Test func oldPreferencesKeepNewDefaultsAndValidateAutoHide() throws {
        let old = Data(#"{"statsEnabled":false,"autoHideSeconds":-1}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: old)
        #expect(!preferences.statsEnabled)
        #expect(preferences.runnerEnabled)
        #expect(!preferences.menuBarEnabled)
        #expect(preferences.autoHideSeconds == 0)
        #expect(preferences.refreshInterval == .balanced)
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        #expect(restored == preferences)
    }

    @Test func menuBarImageAndIconSelectionsSurviveRelaunch() throws {
        var preferences = Preferences()
        preferences.customMenuBarIcon = true
        preferences.customIconTemplate = true
        preferences.menuBarSelectionConfigured = true
        preferences.selectedMenuBarItems = ["com.example.tool|0", "com.example.other|1"]
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        #expect(restored == preferences)
        let old = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        #expect(!old.customMenuBarIcon)
        #expect(!old.menuBarSelectionConfigured)
        #expect(old.selectedMenuBarItems.isEmpty)
    }

    @Test func nativeSamplerReturnsPlausibleReadings() async throws {
        let monitor = SystemMonitor()
        let first = await monitor.sample()
        #expect(first.cpuUsage == nil)
        let memory = try #require(first.memory)
        #expect(memory.totalBytes > 0)
        #expect(memory.usedBytes <= memory.totalBytes)
        #expect(memory.usedBytes + memory.cachedBytes <= memory.totalBytes)
        #expect(memory.compressedBytes <= memory.usedBytes)
        #expect(first.processorCount > 0)
        // macOS can cache host CPU statistics longer than 100 ms. Wait for a
        // changed native tick sample instead of assuming a fixed cache lifetime.
        var usageSample: Double?
        for _ in 0..<8 {
            try await Task.sleep(for: .milliseconds(250))
            usageSample = await monitor.sample().cpuUsage
            if usageSample != nil { break }
        }
        let usage = try #require(usageSample)
        #expect((0...100).contains(usage))
        await monitor.resetBaselines()
        let reset = await monitor.sample(includeDetails: false)
        #expect(reset.cpuUsage == nil)
        #expect(reset.memory == nil)
        #expect(reset.network == nil)
    }
}
