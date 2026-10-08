import BarloomCore
import ServiceManagement
import SwiftUI

struct SettingsPage: View {
    @EnvironmentObject private var model: AppModel
    @State private var loginError: String?
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Surface {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeading(title: "Choose your modules", detail: "Disabled modules stop their background work.")
                    moduleToggle("Menu Bar", detail: "Hidden and always-hidden sections", symbol: "menubar.rectangle", binding: $model.preferences.menuBarEnabled)
                    moduleToggle("System Monitor", detail: "CPU, memory, network, disk capacity, and battery", symbol: "waveform.path.ecg", binding: $model.preferences.statsEnabled)
                    moduleToggle("Runner", detail: "An animated status icon powered by CPU usage", symbol: "cat", binding: $model.preferences.runnerEnabled)
                    moduleToggle("Local Ports", detail: "Local TCP listeners and development process controls", symbol: "network", binding: $model.preferences.portsEnabled)
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 20) {
                    SectionHeading(title: "Menu bar & performance")
                    HStack {
                        SectionHeading(title: "Status widget", detail: "A reading beside Barloom’s icon")
                        Spacer()
                        Picker("Status widget", selection: $model.preferences.statusMetric) {
                            ForEach(StatusMetric.allCases) { metric in Text(metric.title).tag(metric) }
                        }.labelsHidden().frame(width: 190).disabled(!model.preferences.statsEnabled)
                    }
                    HStack {
                        SectionHeading(title: "Sampling interval", detail: "One shared sampler for your widgets and runner")
                        Spacer()
                        Picker("Sampling interval", selection: $model.preferences.refreshInterval) {
                            ForEach(RefreshInterval.allCases) { interval in Text(interval.title).tag(interval) }
                        }.labelsHidden().frame(width: 190)
                    }
                    HStack {
                        SectionHeading(title: "Reduce motion", detail: "Use a still character; also respects macOS accessibility settings")
                        Spacer()
                        Toggle("Reduce motion", isOn: $model.preferences.reduceMotion).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        SectionHeading(title: "Launch at login", detail: "Keep Barloom ready when your Mac starts.")
                        Spacer()
                        Toggle("Launch at login", isOn: Binding(get: { loginEnabled }, set: { enabled in updateLoginItem(enabled) })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                    if SMAppService.mainApp.status == .requiresApproval {
                        Button("Approve in System Settings…") { SMAppService.openSystemSettingsLoginItems() }.font(.system(size: 11))
                    }
                    if let loginError { Text(loginError).font(.system(size: 11)).foregroundStyle(.orange) }
                }
            }
            Surface {
                HStack(alignment: .top, spacing: 14) {
                    BloomLogo(size: 42)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Barloom 0.1.0").font(.system(size: 14, weight: .semibold, design: .rounded))
                        Text("Native Swift 6 · macOS 14 and later").font(.system(size: 11)).foregroundStyle(.secondary)
                        Text("No accounts. No telemetry. All readings stay on your Mac.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset settings") { model.preferences = Preferences(); model.revealAll() }.buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
    }

    private func moduleToggle(_ title: String, detail: String, symbol: String, binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(AppColors.violet).frame(width: 24)
            SectionHeading(title: title, detail: detail)
            Spacer()
            Toggle(title, isOn: binding).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }

    private func updateLoginItem(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
            loginError = nil
        } catch {
            loginEnabled = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
            loginError = error.localizedDescription
        }
    }
}
