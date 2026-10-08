import AppKit
import BarloomCore
import SwiftUI

struct MenuPopover: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                BloomLogo(size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Barloom").font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Your Mac, at a glance.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.openDashboard?(.settings) } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Settings")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.preferences.statsEnabled {
                        HStack(spacing: 10) {
                            MetricCard(title: "CPU", symbol: "cpu", value: MetricFormat.percent(model.snapshot?.cpuUsage), detail: "\(model.snapshot?.processorCount ?? ProcessInfo.processInfo.activeProcessorCount) logical cores", color: AppColors.mint, progress: model.snapshot?.cpuUsage, compact: true)
                            MetricCard(title: "Memory", symbol: "memorychip", value: MetricFormat.percent(model.snapshot?.memory?.usagePercent), detail: model.snapshot?.memory.map { MetricFormat.bytes($0.usedBytes) + " used" } ?? "Waiting for a sample", color: AppColors.violet, progress: model.snapshot?.memory?.usagePercent, compact: true)
                        }
                        HStack {
                            Label(MetricFormat.rate(model.snapshot?.network?.receivedBytesPerSecond), systemImage: "arrow.down")
                            Spacer()
                            Label(MetricFormat.rate(model.snapshot?.network?.sentBytesPerSecond), systemImage: "arrow.up")
                        }.font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).padding(.horizontal, 5)
                    }
                    if model.preferences.menuBarEnabled {
                        Divider()
                        HStack {
                            Label("Hidden icon bar", systemImage: "menubar.rectangle").font(.system(size: 12, weight: .medium))
                            Spacer()
                            Button(model.overflowSection == nil ? "Open bar" : "Close bar") { model.toggleHidden() }.controlSize(.small)
                        }
                        if let notice = model.menuBarNotice { Text(notice).font(.caption).foregroundStyle(.orange) }
                    }
                    if model.preferences.portsEnabled {
                        Divider()
                        HStack {
                            Text("LOCALHOST").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                            Spacer()
                            Button("\(model.ports.count) listeners") { model.openDashboard?(.ports) }
                                .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(AppColors.blue)
                        }
                        VStack(spacing: 1) {
                            if model.ports.isEmpty {
                                Text(model.portError ?? (model.lastPortScan == nil ? "Scanning local ports…" : "No local TCP listeners"))
                                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 12)
                            } else {
                                ForEach(Array(model.ports.prefix(3))) { port in PortSummaryRow(port: port) }
                            }
                        }
                    }
                    if !model.preferences.statsEnabled && !model.preferences.menuBarEnabled && !model.preferences.portsEnabled {
                        VStack(spacing: 14) {
                            Image(systemName: "sparkles").font(.system(size: 30)).foregroundStyle(AppColors.violet)
                            Text("Your menu bar, your way.").font(.system(size: 14, weight: .medium))
                            Text("Choose your modules in Settings to make Barloom yours.").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.vertical, 35)
                    }
                }
            }.scrollIndicators(.hidden)
            Divider()
            HStack {
                Button { model.openDashboard?(.overview) } label: {
                    HStack { Text("Open Dashboard"); Spacer(); Image(systemName: "arrow.up.right") }
                }.buttonStyle(.borderedProminent).tint(AppColors.violet).controlSize(.large)
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).frame(width: 25).help("Quit Barloom")
            }
        }.padding(22).frame(width: 400, height: 510).tint(AppColors.violet)
    }
}
