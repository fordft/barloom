import Foundation

public struct ProcessIdentity: Equatable, Codable, Sendable {
    public let pid: Int32
    public let userID: UInt32
    public let executablePath: String
    public let startSeconds: UInt64
    public let startMicroseconds: UInt64

    public init(pid: Int32, userID: UInt32, executablePath: String, startSeconds: UInt64, startMicroseconds: UInt64) {
        self.pid = pid
        self.userID = userID
        self.executablePath = executablePath
        self.startSeconds = startSeconds
        self.startMicroseconds = startMicroseconds
    }

    public var executableName: String { URL(fileURLWithPath: executablePath).lastPathComponent }
}

public struct ListeningPort: Identifiable, Equatable, Codable, Sendable {
    public var id: String { "\(pid):\(port)" }
    public let pid: Int32
    public let command: String
    public let userID: UInt32?
    public let port: Int
    public var addresses: [String]
    public var identity: ProcessIdentity?

    public init(pid: Int32, command: String, userID: UInt32?, port: Int, addresses: [String], identity: ProcessIdentity? = nil) {
        self.pid = pid
        self.command = command
        self.userID = userID
        self.port = port
        self.addresses = addresses
        self.identity = identity
    }

    public var isDevelopmentProcess: Bool {
        let name = (identity?.executableName ?? command).lowercased()
        return TerminationPolicy.isSupportedExecutable(name) || ["postgres", "redis-server", "mongod", "docker", "com.docker.backend"].contains(name)
    }

    public var localURL: URL? {
        let hosts = addresses.compactMap { address -> String? in
            guard let colon = address.lastIndex(of: ":") else { return nil }
            return String(address[..<colon]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        }
        let host: String
        if let loopback = hosts.first(where: { $0.hasPrefix("127.") }) { host = loopback }
        else if hosts.contains("*") || hosts.contains("localhost") { host = "localhost" }
        else if hosts.contains("0.0.0.0") { host = "127.0.0.1" }
        else { host = "::1" }
        let urlHost = host.contains(":") ? "[\(host)]" : host
        let scheme = [443, 8443].contains(port) ? "https" : "http"
        return URL(string: "\(scheme)://\(urlHost):\(port)")
    }
}

/// Parse lsof's field format instead of columns; process names may contain spaces.
public enum LsofParser {
    public static func parse(_ output: String) -> [ListeningPort] {
        var pid: Int32?
        var command = "Unknown"
        var userID: UInt32?
        var listeners: [String: ListeningPort] = [:]
        for rawLine in output.split(whereSeparator: { $0 == "\n" || $0 == "\0" }) {
            guard let field = rawLine.first else { continue }
            let value = String(rawLine.dropFirst())
            switch field {
            case "p":
                pid = Int32(value)
                command = "Unknown"
                userID = nil
            case "c": command = value
            case "u": userID = UInt32(value)
            case "n":
                guard let pid, pid > 0, let endpoint = endpoint(value) else { continue }
                let key = "\(pid):\(endpoint.port)"
                if var existing = listeners[key] {
                    if !existing.addresses.contains(value) { existing.addresses.append(value) }
                    listeners[key] = existing
                } else {
                    listeners[key] = ListeningPort(pid: pid, command: command, userID: userID, port: endpoint.port, addresses: [value])
                }
            default: continue
            }
        }
        return listeners.values.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    private static func endpoint(_ value: String) -> (port: Int, host: String)? {
        guard !value.contains("->"), let colon = value.lastIndex(of: ":"),
              let port = Int(value[value.index(after: colon)...]), (1...65_535).contains(port) else { return nil }
        let host = String(value[..<colon]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let octets = host.split(separator: ".")
        let loopbackV4 = octets.count == 4 && octets.first == "127" && octets.allSatisfy { Int($0).map { (0...255).contains($0) } == true }
        guard ["*", "0.0.0.0", "::", "::1", "localhost"].contains(host) || loopbackV4 else { return nil }
        return (port, host)
    }
}

public enum TerminationPolicy {
    public static func isSupportedExecutable(_ name: String) -> Bool {
        if ["node", "bun", "deno", "ruby", "php", "java", "uvicorn", "gunicorn"].contains(name) { return true }
        if name == "python" { return true }
        guard name.hasPrefix("python") else { return false }
        let suffix = name.dropFirst(6)
        return !suffix.isEmpty && suffix.first?.isNumber == true && suffix.allSatisfy { $0.isNumber || $0 == "." }
    }

    public static func canStop(_ identity: ProcessIdentity?, currentUserID: UInt32, ownPID: Int32) -> Bool {
        guard let identity, identity.pid > 1, identity.pid != ownPID,
              identity.userID == currentUserID, identity.startSeconds > 0,
              !identity.executablePath.isEmpty else { return false }
        let protectedPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/"]
        guard !protectedPrefixes.contains(where: identity.executablePath.hasPrefix) else { return false }
        return isSupportedExecutable(identity.executableName.lowercased())
    }

    public static func matchesCurrentProcess(_ expected: ProcessIdentity, actual: ProcessIdentity?) -> Bool {
        actual == expected
    }
}
