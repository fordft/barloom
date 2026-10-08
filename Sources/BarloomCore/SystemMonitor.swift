import Darwin
import Foundation
import IOKit.ps

/// One sampler feeds the dashboard, status widget, and animation. No shell commands or elevated privileges.
public actor SystemMonitor {
    private var previousCPU: CPUTicks?
    private var previousNetwork: [String: NetworkCounters] = [:]
    private var previousTime: Double?
    private var cachedDisk: DiskMetrics?
    private var lastDiskRead: Double = -.infinity

    public init() {}

    public func resetBaselines() {
        previousCPU = nil
        previousNetwork = [:]
        previousTime = nil
    }

    public func sample(includeDetails: Bool = true) -> SystemSnapshot {
        let now = ProcessInfo.processInfo.systemUptime
        let cpu = readCPU()
        let interfaces = includeDetails ? readNetwork() : [:]
        let elapsed = previousTime.map { now - $0 }
        // A sleep/wake gap should warm up again instead of showing a misleading long-window average.
        let usableBaseline = elapsed.map { $0 > 0 && $0 < 30 } ?? false
        let cpuUsage = cpu?.usage(since: usableBaseline ? previousCPU : nil)
        let network = usableBaseline ? NetworkMetrics.rates(current: interfaces, previous: previousNetwork, elapsed: elapsed!) : nil
        previousCPU = cpu
        previousNetwork = interfaces
        previousTime = now

        if includeDetails && now - lastDiskRead >= 30 {
            cachedDisk = readDisk()
            lastDiskRead = now
        }

        return SystemSnapshot(
            timestamp: Date(), cpuUsage: cpuUsage, memory: includeDetails ? readMemory() : nil, disk: includeDetails ? cachedDisk : nil,
            network: network, battery: includeDetails ? readBattery() : nil, uptimeSeconds: now,
            processorCount: ProcessInfo.processInfo.activeProcessorCount,
            thermalState: thermalDescription
        )
    }

    private func readCPU() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(user: UInt64(info.cpu_ticks.0), system: UInt64(info.cpu_ticks.1),
                        idle: UInt64(info.cpu_ticks.2), nice: UInt64(info.cpu_ticks.3))
    }

    private func readMemory() -> MemoryMetrics? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        guard result == KERN_SUCCESS, host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        let total = ProcessInfo.processInfo.physicalMemory
        let compressed = UInt64(info.compressor_page_count) * UInt64(pageSize)
        let used = min(total, (UInt64(info.active_count) + UInt64(info.wire_count)) * UInt64(pageSize) + compressed)
        let cached = min(total - used, (UInt64(info.inactive_count) + UInt64(info.speculative_count)) * UInt64(pageSize))
        return MemoryMetrics(totalBytes: total, usedBytes: used, cachedBytes: cached, compressedBytes: compressed)
    }

    private func readDisk() -> DiskMetrics? {
        // Use the writable APFS data volume; the sealed system volume can report misleading capacity.
        let dataVolume = URL(fileURLWithPath: "/System/Volumes/Data", isDirectory: true)
        guard let values = try? dataVolume.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacityForImportantUsage,
              total > 0 else { return nil }
        return DiskMetrics(totalBytes: Int64(total), availableBytes: min(Int64(total), max(0, available)))
    }

    private func readNetwork() -> [String: NetworkCounters] {
        // NET_RT_IFLIST2 exposes 64-bit counters. getifaddrs' 32-bit byte counters wrap every 4 GB.
        var query: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&query, UInt32(query.count), nil, &size, nil, 0) == 0, size > 0 else { return [:] }
        var buffer = Data(count: size)
        let success = buffer.withUnsafeMutableBytes { bytes in
            sysctl(&query, UInt32(query.count), bytes.baseAddress, &size, nil, 0)
        }
        guard success == 0 else { return [:] }
        var result: [String: NetworkCounters] = [:]
        buffer.withUnsafeBytes { bytes in
            var offset = 0
            while offset + 4 <= size {
                let messageLength = Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard messageLength >= 4, offset + messageLength <= size else { break }
                defer { offset += messageLength }
                guard bytes[offset + 3] == UInt8(RTM_IFINFO2), messageLength >= MemoryLayout<if_msghdr2>.size else { continue }
                let info = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                guard info.ifm_flags & IFF_UP != 0 else { continue }
                var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                guard if_indextoname(UInt32(info.ifm_index), &nameBuffer) != nil else { continue }
                let name = String(decoding: nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                // Virtual bridges/VPNs can duplicate the physical interface's traffic.
                guard name.hasPrefix("en") else { continue }
                result[name] = NetworkCounters(received: info.ifm_data.ifi_ibytes, sent: info.ifm_data.ifi_obytes)
            }
        }
        return result
    }

    private func readBattery() -> BatteryMetrics? {
        guard let rawInfo = IOPSCopyPowerSourcesInfo() else { return nil }
        let info = rawInfo.takeRetainedValue()
        guard let rawSources = IOPSCopyPowerSourcesList(info) else { return nil }
        let sources = rawSources.takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let rawDescription = IOPSGetPowerSourceDescription(info, source),
                  let description = rawDescription.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let pluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let minutes = description[charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int
            return BatteryMetrics(percent: min(100, max(0, Int(Double(current) / Double(maximum) * 100))),
                                  isCharging: charging, isPluggedIn: pluggedIn, minutesRemaining: minutes.flatMap { $0 > 0 ? $0 : nil })
        }
        return nil
    }

    private var thermalDescription: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "Nominal"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }
}
