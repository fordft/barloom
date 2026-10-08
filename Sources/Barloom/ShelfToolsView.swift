import BarloomCore
import SwiftUI

/// Barloom's own tools live inside the shelf, independently of captured status items.
struct ShelfToolsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var portQuery = ""

    let page: ShelfToolPage
    let selectPage: (ShelfToolPage) -> Void
    let openPage: (DashboardPage) -> Void

    private var matchingPorts: [ListeningPort] {
        let query = portQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return model.ports }
        return model.ports.filter {
            $0.command.lowercased().contains(query) || String($0.port).contains(query) || String($0.pid).contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Barloom").font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("Your Mac, at a glance").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Picker("", selection: Binding(get: { page }, set: { selectPage($0) })) {
                    Text("Overview").tag(ShelfToolPage.overview)
                    Text("Port Manager").tag(ShelfToolPage.ports)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Barloom page")
                .frame(width: 242)
            }

            if page == .overview { overview }
            else { ports }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tint(AppColors.violet)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                MetricCard(title: "CPU", symbol: "cpu", value: MetricFormat.percent(model.snapshot?.cpuUsage),
                           detail: "\(model.snapshot?.processorCount ?? ProcessInfo.processInfo.activeProcessorCount) logical cores",
                           color: AppColors.mint, progress: model.snapshot?.cpuUsage, compact: true)
                MetricCard(title: "RAM", symbol: "memorychip", value: MetricFormat.percent(model.snapshot?.memory?.usagePercent),
                           detail: model.snapshot?.memory.map { MetricFormat.bytes($0.usedBytes) + " used" } ?? "Waiting for a sample",
                           color: AppColors.violet, progress: model.snapshot?.memory?.usagePercent, compact: true)
                MetricCard(title: "Battery", symbol: "battery.100percent",
                           value: model.snapshot?.battery.map { "\($0.percent)%" } ?? "—",
                           detail: batteryDetail, color: AppColors.amber,
                           progress: model.snapshot?.battery.map { Double($0.percent) }, compact: true)
            }
            HStack(spacing: 14) {
                Label("↓ " + MetricFormat.rate(model.snapshot?.network?.receivedBytesPerSecond), systemImage: "network")
                Label("↑ " + MetricFormat.rate(model.snapshot?.network?.sentBytesPerSecond), systemImage: "arrow.up")
                Spacer(minLength: 0)
                if let disk = model.snapshot?.disk {
                    Label(MetricFormat.bytes(UInt64(max(0, disk.availableBytes))) + " free", systemImage: "internaldrive")
                }
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)

            Divider()
            HStack {
                Label("Local ports", systemImage: "network")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(model.ports.count) listening").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if model.preferences.portsEnabled {
                if model.ports.isEmpty {
                    Text(model.portError ?? (model.isScanning ? "Scanning local ports…" : "No local TCP listeners"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 5) {
                        ForEach(Array(model.ports.prefix(2))) { port in
                            HStack(spacing: 8) {
                                Text(":\(port.port)").font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(AppColors.blue).frame(width: 58, alignment: .leading)
                                Text(port.command).font(.system(size: 11)).lineLimit(1)
                                Spacer(minLength: 0)
                                Text("PID \(port.pid)").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Text("Port Manager is off in Settings.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack {
                if !model.preferences.statsEnabled {
                    Button("Enable System Monitor") { model.preferences.statsEnabled = true }
                        .controlSize(.small)
                }
                Spacer()
                Button("Port Manager") { selectPage(.ports) }
                    .controlSize(.small).buttonStyle(.borderedProminent)
                Button("Full dashboard") { openPage(.overview) }
                    .controlSize(.small).buttonStyle(.bordered)
            }
        }
    }

    private var batteryDetail: String {
        guard let battery = model.snapshot?.battery else { return "No battery data" }
        if battery.isCharging { return "Charging" }
        return battery.isPluggedIn ? "Plugged in" : "On battery"
    }

    private var ports: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Search process, port, or PID", text: $portQuery)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search listening ports")
                Button { Task { await model.refreshPorts() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(model.isScanning || !model.preferences.portsEnabled)
                    .help("Refresh ports")
            }
            HStack {
                Text("\(matchingPorts.count) \(matchingPorts.count == 1 ? "listener" : "listeners")")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                if model.isScanning { ProgressView().controlSize(.mini) }
                else if let last = model.lastPortScan {
                    Text("Updated \(last, style: .time)").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            if !model.preferences.portsEnabled {
                VStack(spacing: 10) {
                    Text("Port Manager is off").font(.system(size: 12, weight: .medium))
                    Button("Enable Port Manager") { model.preferences.portsEnabled = true }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if matchingPorts.isEmpty {
                Text(model.portError ?? (model.isScanning ? "Scanning local ports…" : "No matching local listeners"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(matchingPorts) { port in
                            HStack(spacing: 10) {
                                Text(":\(port.port)")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(AppColors.blue).frame(width: 72, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(port.command).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                    Text("PID \(port.pid) · \(port.addresses.joined(separator: ", "))")
                                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 2)
                                Button { model.copyURL(port) } label: { Image(systemName: "doc.on.doc") }
                                    .help("Copy localhost URL")
                                Button { model.openPort(port) } label: { Image(systemName: "arrow.up.right.square") }
                                    .disabled(port.localURL == nil).help("Open localhost URL")
                            }
                            .padding(.vertical, 7)
                            Divider()
                        }
                    }
                }
                .scrollIndicators(.automatic)
            }
            HStack {
                Text("Use the full manager to stop supported processes.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Open full Port Manager") { openPage(.ports) }
                    .controlSize(.small).buttonStyle(.borderedProminent)
            }
        }
    }
}
