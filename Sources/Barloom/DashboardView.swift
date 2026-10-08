import AppKit
import BarloomCore
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                header
                ScrollView {
                    Group {
                        switch model.selectedPage {
                        case .overview: OverviewPage()
                        case .menuBar: MenuBarPage()
                        case .system: SystemPage()
                        case .runner: RunnerPage()
                        case .ports: PortsPage()
                        case .settings: SettingsPage()
                        }
                    }.padding(26).frame(maxWidth: 1_150, alignment: .topLeading).frame(maxWidth: .infinity)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(AppColors.violet)
        .frame(minWidth: 840, minHeight: 570)
        .preferredColorScheme(nil)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BloomLogo(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Barloom").font(.system(size: 19, weight: .bold, design: .rounded))
                    Text("A home for your menu bar").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 18).padding(.top, 28).padding(.bottom, 32)
            Text("WORKSPACE").font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(.tertiary)
                .padding(.horizontal, 22).padding(.bottom, 10)
            ForEach(DashboardPage.allCases.filter { $0 != .settings }) { page in
                navigationButton(page)
            }
            Spacer()
            HStack(spacing: 7) {
                Image(systemName: "lock.shield").foregroundStyle(AppColors.mint)
                Text("On your Mac. Only.").foregroundStyle(.secondary)
            }.font(.system(size: 10)).padding(.horizontal, 22).padding(.bottom, 18)
            Divider().padding(.horizontal, 18)
            navigationButton(.settings).padding(.top, 10).padding(.bottom, 18)
        }.frame(width: 204).background(.thinMaterial)
    }

    private func navigationButton(_ page: DashboardPage) -> some View {
        Button { model.selectedPage = page } label: {
            HStack(spacing: 11) {
                Image(systemName: page.symbol).font(.system(size: 14)).frame(width: 18)
                Text(page.title).font(.system(size: 12, weight: model.selectedPage == page ? .semibold : .regular))
                Spacer()
                if page == .ports && model.preferences.portsEnabled {
                    Text("\(model.ports.count)").font(.system(size: 10, weight: .medium)).monospacedDigit()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.primary.opacity(0.06), in: Capsule())
                }
            }
            .foregroundStyle(model.selectedPage == page ? AppColors.violet : Color.primary.opacity(0.72))
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(model.selectedPage == page ? AppColors.violet.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.horizontal, 10).padding(.vertical, 2)
        .accessibilityAddTraits(model.selectedPage == page ? .isSelected : [])
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.selectedPage.title).font(.system(size: 24, weight: .semibold, design: .rounded))
                Text(model.selectedPage.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if model.preferences.statsEnabled || model.preferences.runnerEnabled {
                StatusPill(title: model.isSleeping ? "Paused" : "Live · \(model.preferences.refreshInterval.rawValue)s", color: model.isSleeping ? .secondary : AppColors.mint)
            } else {
                StatusPill(title: "Local", color: AppColors.violet)
            }
        }.padding(.horizontal, 28).padding(.vertical, 24)
        .overlay(alignment: .bottom) { Divider().opacity(0.65) }
    }
}

struct OverviewPage: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("A clearer view of your Mac.").font(.system(size: 18, weight: .medium, design: .rounded))
                Spacer()
                Text("\(model.activeModuleCount) of 4 modules active").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if model.preferences.statsEnabled {
                SystemMetricCards()
                Surface {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            SectionHeading(title: "The pulse of your Mac", detail: "Recent CPU and memory usage")
                            Spacer()
                            ChartLegend()
                        }
                        HistoryChart(samples: model.history, height: 140)
                    }
                }
            }
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 14) {
                ModuleCard(title: "Menu Bar", detail: "Give your icons a little breathing room.", symbol: "menubar.rectangle", color: AppColors.violet, enabled: $model.preferences.menuBarEnabled, page: .menuBar)
                ModuleCard(title: "System Monitor", detail: "Live readings. One shared engine.", symbol: "waveform.path.ecg", color: AppColors.mint, enabled: $model.preferences.statsEnabled, page: .system)
                ModuleCard(title: "Runner", detail: "A companion that moves with your CPU.", symbol: "cat", color: AppColors.amber, enabled: $model.preferences.runnerEnabled, page: .runner)
                ModuleCard(title: "Local Ports", detail: "Your development servers, within reach.", symbol: "network", color: AppColors.blue, enabled: $model.preferences.portsEnabled, page: .ports)
            }
            if model.preferences.portsEnabled {
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            SectionHeading(title: "Listening on localhost", detail: "\(model.ports.count) \(model.ports.count == 1 ? "listener" : "listeners") available to your user")
                            Spacer()
                            Button("View all") { model.selectedPage = .ports }.buttonStyle(.plain).foregroundStyle(AppColors.violet).font(.system(size: 11, weight: .medium))
                        }
                        if model.ports.isEmpty {
                            Text(model.lastPortScan == nil ? "Scanning local ports…" : "No TCP listeners found on localhost.")
                                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 10)
                        } else {
                            ForEach(Array(model.ports.prefix(3))) { port in PortSummaryRow(port: port) }
                        }
                        if let error = model.portError { Text(error).font(.caption).foregroundStyle(.orange) }
                    }
                }
            }
        }
    }
}

struct ModuleCard: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    @Binding var enabled: Bool
    let page: DashboardPage
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(color)
                        .frame(width: 36, height: 36).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    Spacer()
                    Toggle(title, isOn: $enabled).toggleStyle(.switch).controlSize(.small).labelsHidden().help("Enable \(title)")
                }
                Button { model.selectedPage = page } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(title).font(.system(size: 13, weight: .semibold))
                            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer(minLength: 3)
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }
}

struct SystemMetricCards: View {
    @EnvironmentObject private var model: AppModel
    var compact = false
    var body: some View {
        let snapshot = model.snapshot
        let memory = snapshot?.memory
        LazyVGrid(columns: Array(repeating: .init(.flexible(), spacing: 12), count: compact ? 2 : 4), spacing: 12) {
            MetricCard(title: "CPU", symbol: "cpu", value: MetricFormat.percent(snapshot?.cpuUsage), detail: "\(snapshot?.processorCount ?? ProcessInfo.processInfo.activeProcessorCount) logical cores", color: AppColors.mint, progress: snapshot?.cpuUsage, compact: compact)
            MetricCard(title: "Memory", symbol: "memorychip", value: MetricFormat.percent(memory?.usagePercent), detail: memory.map { "\(MetricFormat.bytes($0.usedBytes)) of \(MetricFormat.bytes($0.totalBytes))" } ?? "Waiting for a sample", color: AppColors.violet, progress: memory?.usagePercent, compact: compact)
            MetricCard(title: "Disk free", symbol: "internaldrive", value: snapshot?.disk.map { MetricFormat.bytes(UInt64($0.availableBytes)) } ?? "—", detail: "APFS data volume", color: AppColors.blue, progress: snapshot?.disk?.usagePercent, compact: compact)
            MetricCard(title: "Power", symbol: snapshot?.battery?.isPluggedIn == true ? "powerplug" : "battery.75percent", value: snapshot?.battery.map { "\($0.percent)%" } ?? (snapshot == nil ? "—" : "AC"), detail: snapshot?.battery.map { $0.isCharging ? "Charging" : ($0.isPluggedIn ? "Plugged in" : "On battery") } ?? "No internal battery", color: AppColors.amber, progress: snapshot?.battery.map { Double($0.percent) }, compact: compact)
        }
    }
}

struct SystemPage: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        if !model.preferences.statsEnabled {
            DisabledModule(title: "System Monitor", symbol: "waveform.path.ecg") { model.preferences.statsEnabled = true }
        } else {
            VStack(spacing: 20) {
                SystemMetricCards()
                Surface {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack { SectionHeading(title: "Usage over time", detail: "Up to 90 samples · \(model.preferences.refreshInterval.rawValue)s interval"); Spacer(); ChartLegend() }
                        HistoryChart(samples: model.history, height: 200)
                    }
                }
                HStack(alignment: .top, spacing: 16) {
                    Surface {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeading(title: "Network", detail: "Physical Ethernet and Wi-Fi interfaces")
                            DetailRow(title: "↓ Download", value: MetricFormat.rate(model.snapshot?.network?.receivedBytesPerSecond))
                            DetailRow(title: "↑ Upload", value: MetricFormat.rate(model.snapshot?.network?.sentBytesPerSecond))
                            Divider()
                            Text("Loopback and virtual interfaces are excluded to avoid counting traffic twice.").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    Surface {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeading(title: "Your system")
                            DetailRow(title: "Uptime", value: MetricFormat.uptime(model.snapshot?.uptimeSeconds ?? 0))
                            DetailRow(title: "Thermal state", value: model.snapshot?.thermalState ?? "—")
                            DetailRow(title: "Compressed RAM", value: model.snapshot?.memory.map { MetricFormat.bytes($0.compressedBytes) } ?? "—")
                            DetailRow(title: "Cached RAM", value: model.snapshot?.memory.map { MetricFormat.bytes($0.cachedBytes) } ?? "—")
                        }
                    }
                }
                Text("Memory usage includes active, wired, and compressed memory. GPU monitoring and disk I/O are next on the roadmap.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
