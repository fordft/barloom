import Darwin
import Foundation

public enum PortError: Error, LocalizedError, Sendable {
    case scanFailed(String), notSupported, processChanged, signalFailed(Int32)
    public var errorDescription: String? {
        switch self {
        case .scanFailed(let message): "Could not scan ports: \(message)"
        case .notSupported: "Only supported development processes owned by your user can be stopped."
        case .processChanged: "This process has changed or exited. Refresh the port list before trying again."
        case .signalFailed(let code): "macOS could not stop this process (error \(code))."
        }
    }
}

public enum ProcessInspector {
    public static func identity(pid: Int32) -> ProcessIdentity? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == Int32(size) else { return nil }
        // The SDK's (4 * MAXPATHLEN) macro is not imported by Swift.
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &path, UInt32(path.count))
        guard length > 0 else { return nil }
        let executablePath = String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return ProcessIdentity(pid: pid, userID: info.pbi_uid, executablePath: executablePath,
                               startSeconds: info.pbi_start_tvsec, startMicroseconds: info.pbi_start_tvusec)
    }
}

public actor PortScanner {
    public init() {}

    public func scan() async throws -> [ListeningPort] {
        let result = try await CommandRunner.run(executable: "/usr/sbin/lsof", arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcufn"])
        // lsof uses exit code 1 for an empty selection. Stderr means the scan itself failed.
        guard result.exitCode == 0 || (result.exitCode == 1 && result.output.isEmpty && result.errorOutput.isEmpty) else {
            throw PortError.scanFailed(result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240).description)
        }
        var ports = LsofParser.parse(result.output)
        var identities: [Int32: ProcessIdentity] = [:]
        for index in ports.indices {
            let pid = ports[index].pid
            let identity = identities[pid] ?? ProcessInspector.identity(pid: pid)
            identities[pid] = identity
            ports[index].identity = identity
        }
        return ports
    }

    public func stop(_ port: ListeningPort) async throws {
        guard let expected = port.identity,
              TerminationPolicy.canStop(expected, currentUserID: getuid(), ownPID: getpid()) else { throw PortError.notSupported }
        let currentPorts = try await scan()
        guard currentPorts.contains(where: { $0.id == port.id && $0.identity == expected }),
              TerminationPolicy.matchesCurrentProcess(expected, actual: ProcessInspector.identity(pid: port.pid)) else {
            throw PortError.processChanged
        }
        // Signal this PID only; do not kill a process group or escalate to SIGKILL.
        guard Darwin.kill(port.pid, SIGTERM) == 0 else { throw PortError.signalFailed(errno) }
    }
}
