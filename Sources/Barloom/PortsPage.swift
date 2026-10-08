import BarloomCore
import SwiftUI

struct PortsPage: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var developmentOnly = false
    @State private var pendingStop: ListeningPort?

    private var filteredPorts: [ListeningPort] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return model.ports.filter {
            (!developmentOnly || $0.isDevelopmentProcess) &&
            (query.isEmpty || $0.command.lowercased().contains(query) || String($0.port).contains(query) || String($0.pid).contains(query))
        }
    }

    var body: some View {
        if !model.preferences.portsEnabled {
            DisabledModule(title: "Local Ports", symbol: "network") { model.preferences.portsEnabled = true }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    TextField("Search process, port, or PID", text: $query).textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300).accessibilityLabel("Search listening ports")
                    Picker("Processes", selection: $developmentOnly) {
                        Text("All").tag(false)
                        Text("Development").tag(true)
                    }.pickerStyle(.segmented).frame(width: 170)
                    Spacer(minLength: 0)
                    Button { Task { await model.refreshPorts() } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }.disabled(model.isScanning).buttonStyle(.bordered)
                }
                if let error = model.portError {
                    Surface {
                        HStack(alignment: .top) {
                            Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.orange)
                            Spacer()
                            Button { model.portError = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                        }
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            SectionHeading(title: "\(filteredPorts.count) \(filteredPorts.count == 1 ? "listener" : "listeners")", detail: "TCP sockets reachable on localhost")
                            Spacer()
                            if model.isScanning { ProgressView().controlSize(.small).scaleEffect(0.7) }
                            else { StatusPill(title: "Local discovery", color: AppColors.blue) }
                        }
                        Divider()
                        if filteredPorts.isEmpty {
                            VStack(spacing: 14) {
                                Image(systemName: query.isEmpty ? "network" : "magnifyingglass").font(.system(size: 30)).foregroundStyle(.tertiary)
                                Text(emptyMessage).font(.system(size: 13, weight: .medium))
                                Text(query.isEmpty ? "Start a local server and refresh to see it here." : "Try another process name or port number.")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 40)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredPorts) { port in
                                    portRow(port)
                                    if port.id != filteredPorts.last?.id { Divider().opacity(0.6) }
                                }
                            }
                        }
                    }
                }
                HStack {
                    Text("Scans every 5s while the dashboard is open, every 20s in the background.")
                    Spacer()
                    if let last = model.lastPortScan { Text(last, style: .time) }
                }.font(.system(size: 10)).foregroundStyle(.secondary)
                Surface {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "hand.raised").foregroundStyle(AppColors.blue)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("You stay in control").font(.system(size: 12, weight: .semibold))
                            Text("Stop is available for supported development processes owned by your user. Barloom checks the process identity again and sends a graceful stop signal after confirmation.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Text("Open assumes HTTP, or HTTPS on ports 443 and 8443. Database and other non-web listeners may not open in a browser.")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .confirmationDialog("Stop \(pendingStop?.command ?? "process")?", isPresented: Binding(get: { pendingStop != nil }, set: { if !$0 { pendingStop = nil } }), titleVisibility: .visible, presenting: pendingStop) { port in
                Button("Stop Process", role: .destructive) {
                    pendingStop = nil
                    Task { await model.stopProcess(port) }
                }
                Button("Cancel", role: .cancel) { pendingStop = nil }
            } message: { port in
                Text("Send SIGTERM to PID \(port.pid). Other listeners from this process will also close.")
            }
        }
    }

    private var emptyMessage: String {
        if model.lastPortScan == nil && model.isScanning { return "Scanning local ports…" }
        if !query.isEmpty { return "No matching listeners" }
        if developmentOnly { return "No development listeners found" }
        return "Localhost is quiet"
    }

    private func portRow(_ port: ListeningPort) -> some View {
        HStack(spacing: 14) {
            Text(":\(String(port.port))").font(.system(size: 16, weight: .semibold, design: .monospaced)).foregroundStyle(AppColors.blue).frame(width: 78, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(port.command).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if model.sharedPorts.contains(port.port) {
                        Text("Shared").font(.system(size: 9, weight: .medium)).foregroundStyle(AppColors.amber)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(AppColors.amber.opacity(0.10), in: Capsule())
                            .help("Multiple processes use this port. Listeners on separate addresses can coexist.")
                    }
                }
                Text("PID \(port.pid) · \(port.addresses.joined(separator: ", "))")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if model.stoppingPID == port.pid { ProgressView().controlSize(.small) }
            Button { model.copyURL(port) } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless).foregroundStyle(.secondary).help("Copy localhost URL")
            Button { model.openPort(port) } label: { Image(systemName: "arrow.up.right.square") }
                .buttonStyle(.borderless).foregroundStyle(AppColors.blue).help("Open localhost URL")
            Button { pendingStop = port } label: { Image(systemName: "stop.circle") }
                .buttonStyle(.borderless).foregroundStyle(model.canStop(port) ? .orange : .secondary)
                .disabled(!model.canStop(port) || model.stoppingPID != nil)
                .help(model.canStop(port) ? "Stop this development process…" : "Stopping this process is not supported")
        }.padding(.vertical, 14)
        .contextMenu {
            Button("Open Localhost URL") { model.openPort(port) }
            Button("Copy URL") { model.copyURL(port) }
            if model.canStop(port) { Button("Stop Process…", role: .destructive) { pendingStop = port } }
        }
    }
}
