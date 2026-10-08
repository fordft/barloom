import Darwin
import Foundation
import Testing
@testable import BarloomCore

@Suite("Local port discovery and controls")
struct PortTests {
    @Test func fieldParserPreservesNamesAndCombinesDualStackListeners() throws {
        let output = """
        p101
        cMy Dev Server
        u501
        f12
        n127.0.0.1:3000
        f13
        n[::1]:3000
        f14
        n[::1]:3000
        p202
        cnode
        u501
        f8
        n*:8080
        p303
        cssh
        u501
        f9
        n[::1]:2222
        """
        let ports = LsofParser.parse(output)
        #expect(ports.map(\.port) == [2222, 3000, 8080])
        let server = try #require(ports.first { $0.pid == 101 })
        #expect(server.command == "My Dev Server")
        #expect(server.addresses == ["127.0.0.1:3000", "[::1]:3000"])
        #expect(server.userID == 501)
        #expect(server.localURL?.absoluteString == "http://127.0.0.1:3000")
        #expect(ports.first?.localURL?.absoluteString == "http://[::1]:2222")
    }

    @Test func parserRejectsRemoteBindingsConnectionsAndMalformedPorts() {
        let output = """
        n*:3000
        p100
        cnode
        n192.168.1.10:3000
        n127.0.0.1:3000->127.0.0.1:5000
        n*:0
        n*:65536
        nmalformed
        n127.999.0.1:3000
        n127.0.0.2:4000
        n0.0.0.0:8443
        p200
        cbun
        n[::]:4000
        """
        let ports = LsofParser.parse(output)
        #expect(ports.count == 3)
        #expect(ports.filter { $0.port == 4000 }.count == 2)
        #expect(ports.first { $0.port == 8443 }?.localURL?.scheme == "https")
    }

    @Test func urlsPreserveLoopbackBindingsAndHandleWildcardFamilies() {
        let ports = LsofParser.parse("p100\ncnode\nn127.0.0.2:3000\nn*:3001\nn[::]:3002\nn0.0.0.0:3003\n")
        #expect(ports.map { $0.localURL?.absoluteString } == [
            "http://127.0.0.2:3000", "http://localhost:3001", "http://[::1]:3002", "http://127.0.0.1:3003"
        ])
    }

    @Test func stopPolicyProtectsOtherUsersSystemProcessesAndOwnPID() {
        func identity(pid: Int32 = 100, uid: UInt32 = 501, path: String = "/opt/homebrew/bin/node") -> ProcessIdentity {
            ProcessIdentity(pid: pid, userID: uid, executablePath: path, startSeconds: 1_000, startMicroseconds: 50)
        }
        #expect(TerminationPolicy.canStop(identity(), currentUserID: 501, ownPID: 500))
        #expect(!TerminationPolicy.canStop(nil, currentUserID: 501, ownPID: 500))
        #expect(!TerminationPolicy.canStop(identity(uid: 0), currentUserID: 501, ownPID: 500))
        #expect(!TerminationPolicy.canStop(identity(pid: 1), currentUserID: 501, ownPID: 500))
        #expect(!TerminationPolicy.canStop(identity(pid: 500), currentUserID: 501, ownPID: 500))
        #expect(!TerminationPolicy.canStop(identity(path: "/System/Library/node"), currentUserID: 501, ownPID: 500))
        #expect(!TerminationPolicy.canStop(identity(path: "/usr/libexec/python3"), currentUserID: 501, ownPID: 500))
        #expect(!TerminationPolicy.canStop(identity(path: "/Applications/ControlCenter"), currentUserID: 501, ownPID: 500))
        #expect(TerminationPolicy.isSupportedExecutable("python3.12"))
        #expect(!TerminationPolicy.isSupportedExecutable("python-helper"))
    }

    @Test func reusedPIDsDoNotMatchTheRecordedIdentity() {
        let old = ProcessIdentity(pid: 100, userID: 501, executablePath: "/opt/homebrew/bin/node", startSeconds: 1_000, startMicroseconds: 10)
        let reused = ProcessIdentity(pid: 100, userID: 501, executablePath: old.executablePath, startSeconds: 1_001, startMicroseconds: 10)
        #expect(!TerminationPolicy.matchesCurrentProcess(old, actual: reused))
        #expect(!TerminationPolicy.matchesCurrentProcess(old, actual: nil))
        #expect(TerminationPolicy.matchesCurrentProcess(old, actual: old))
    }

    @Test func nativeIdentityMatchesTheCurrentProcess() throws {
        let identity = try #require(ProcessInspector.identity(pid: getpid()))
        #expect(identity.pid == getpid())
        #expect(identity.userID == getuid())
        #expect(!identity.executablePath.isEmpty)
        #expect(identity.startSeconds > 0)
        #expect(identity == ProcessInspector.identity(pid: getpid()))
    }

    @Test func commandDrainsBothPipesWithoutDeadlocking() async throws {
        let script = #"BEGIN { for (i=0; i<12000; i++) { print "stdout line of useful output"; print "stderr line of useful output" > "/dev/stderr" } }"#
        let result = try await CommandRunner.run(executable: "/usr/bin/awk", arguments: [script], timeout: 5)
        #expect(result.exitCode == 0)
        #expect(result.output.split(separator: "\n").count == 12_000)
        #expect(result.errorOutput.split(separator: "\n").count == 12_000)
    }

    @Test func commandTimeoutEndsOnlyItsOwnChild() async {
        do {
            _ = try await CommandRunner.run(executable: "/bin/sleep", arguments: ["5"], timeout: 0.1)
            Issue.record("Expected the command to time out")
        } catch CommandError.timedOut {
            // Expected.
        } catch {
            Issue.record("Unexpected timeout error: \(error)")
        }
    }

    @Test func cancelledCommandReleasesItsChild() async throws {
        let task = Task { try await CommandRunner.run(executable: "/bin/sleep", arguments: ["5"], timeout: 10) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }

    @Test func commandOutputLimitIsEnforced() async {
        do {
            _ = try await CommandRunner.run(executable: "/usr/bin/awk", arguments: [#"BEGIN { for (i=0; i<100000; i++) print "a line that exceeds the output budget" }"#])
            Issue.record("Expected output to be capped")
        } catch CommandError.outputTooLarge {
            // Expected. The runner also waits for its child to exit on this path.
        } catch {
            Issue.record("Unexpected output-limit error: \(error)")
        }
    }

    @Test func scannerFindsAndGracefullyStopsItsOwnDevelopmentFixture() async throws {
        let child = Process()
        let output = Pipe()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        child.arguments = ["-u", "-c", "import socket,time; s=socket.socket(); s.bind(('127.0.0.1',0)); s.listen(); print(s.getsockname()[1],flush=True); time.sleep(30)"]
        child.standardOutput = output
        try child.run()
        defer {
            if child.isRunning { child.terminate() }
            child.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        // This fixture prints one port number and then waits. No existing listener is touched.
        var line = Data()
        while let byte = try output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty, byte.first != 10 { line.append(byte) }
        let portNumber = try #require(Int(String(decoding: line, as: UTF8.self)))
        let scanner = PortScanner()
        let listeners = try await scanner.scan()
        let listener = try #require(listeners.first { $0.pid == child.processIdentifier && $0.port == portNumber })
        #expect(listener.command.lowercased().contains("python"))
        #expect(TerminationPolicy.canStop(listener.identity, currentUserID: getuid(), ownPID: getpid()))
        try await scanner.stop(listener)
        child.waitUntilExit()
        #expect(child.terminationReason == .uncaughtSignal)
        #expect(child.terminationStatus == SIGTERM)
        let after = try await scanner.scan()
        #expect(!after.contains { $0.id == listener.id })
    }
}
