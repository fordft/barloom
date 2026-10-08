import AppKit
import SwiftUI

struct MenuBarPage: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Surface {
                HStack(spacing: 16) {
                    Image(systemName: "menubar.rectangle").font(.system(size: 28)).foregroundStyle(AppColors.violet)
                    SectionHeading(title: "A second bar, below the notch", detail: "Hidden icons open in a separate horizontal bar.")
                    Spacer()
                    Toggle("Enable Menu Bar", isOn: $model.preferences.menuBarEnabled).labelsHidden().toggleStyle(.switch)
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 20) {
                    SectionHeading(title: "Your hidden icon bar", detail: "Click Barloom to open it. Click again, outside the bar, or press Escape to close it.")
                    HStack(spacing: 8) {
                        Image(systemName: "menubar.rectangle").font(.system(size: 18)).foregroundStyle(.secondary)
                        Text("Main menu bar").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        BloomLogo(size: 26)
                    }.padding(12).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                    HStack(spacing: 16) {
                        Image(systemName: "arrow.down").foregroundStyle(AppColors.violet)
                        Text("Hidden icons appear here, underneath the menu bar.")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(AppColors.violet)
                        Spacer()
                    }.padding(14).background(AppColors.violet.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                    Text("Long rows scroll within your display. Clicking an icon opens its app’s native menu at the system menu bar; macOS does not let Barloom move another app’s menu below this shelf.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack {
                        Button(model.overflowSection == nil ? "Open icon bar" : "Close icon bar") { model.toggleHidden() }
                            .buttonStyle(.borderedProminent)
                        Button("Open all hidden icons") { model.revealAll() }
                            .buttonStyle(.bordered)
                        Spacer()
                    }.disabled(!model.preferences.menuBarEnabled)
                    if let notice = model.menuBarNotice {
                        HStack(alignment: .top) {
                            Label(notice, systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(.orange)
                            Spacer()
                            Button { model.menuBarNotice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeading(title: "One icon. Your choice.", detail: "Only Barloom’s control is visible on the menu bar. Choose your own image for it.")
                    HStack(spacing: 16) {
                        if let image = model.customMenuBarImage {
                            Image(nsImage: image).resizable().scaledToFit().frame(width: 36, height: 36)
                        } else { BloomLogo(size: 36) }
                        Button("Choose image…") { model.chooseMenuBarIcon() }
                        if model.preferences.customMenuBarIcon {
                            Button("Use default icon") { model.resetMenuBarIcon() }
                        }
                        Spacer()
                    }
                    if model.preferences.customMenuBarIcon {
                        Toggle("Use monochrome tint", isOn: $model.preferences.customIconTemplate).toggleStyle(.switch).controlSize(.small)
                    }
                }
            }
            MenuBarLibraryView(library: model.menuBarLibrary)
            MenuBarPermissionCard(access: model.menuBarAccess)
            Surface {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeading(title: "A single visible button", detail: "Click your Barloom icon to toggle the separate bar below it. There are no divider buttons to click.")
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "Open and close, your way")
                    DetailRow(title: "Click Barloom", value: "Toggle the separate icon bar")
                    DetailRow(title: "Shift-click Barloom", value: "Open Quick Monitor")
                    DetailRow(title: "Escape or click outside", value: "Close the icon bar")
                    DetailRow(title: "Global shortcut", value: model.shortcutAvailable ? "⌃ ⌥ B" : (model.preferences.menuBarEnabled ? "Unavailable · already in use" : "Enable Menu Bar first"))
                    Divider()
                    HStack {
                        Text("Automatically close the icon bar").font(.system(size: 12))
                        Spacer()
                        Picker("Automatically close", selection: $model.preferences.autoHideSeconds) {
                            Text("Keep open").tag(0)
                            Text("5 seconds").tag(5)
                            Text("10 seconds").tag(10)
                            Text("30 seconds").tag(30)
                        }.labelsHidden().frame(width: 160)
                    }.disabled(!model.preferences.menuBarEnabled)
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "Connected displays", detail: "The icon bar opens below the menu bar on the display you are using.")
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { _, screen in
                        HStack {
                            Image(systemName: screen.safeAreaInsets.top > 0 ? "laptopcomputer" : "display").foregroundStyle(.secondary)
                            Text(screen.localizedName).font(.system(size: 12))
                            Spacer()
                            Text("\(Int(screen.frame.width)) × \(Int(screen.frame.height)) pt").font(.system(size: 11)).foregroundStyle(.secondary)
                            if screen.safeAreaInsets.top > 0 { StatusPill(title: "Notch", color: AppColors.violet) }
                        }
                    }
                }
            }
        }
    }
}

struct MenuBarPermissionCard: View {
    @ObservedObject var access: MenuBarAccess
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeading(title: "Allow your icon bar to work", detail: "macOS protects icons and controls belonging to other apps.")
                HStack {
                    Image(systemName: "rectangle.dashed").foregroundStyle(AppColors.violet).frame(width: 24)
                    SectionHeading(title: "Screen Recording", detail: "Read the icon images. Captures stay in memory on your Mac; no audio is captured.")
                    Spacer()
                    if access.canCapture { StatusPill(title: "Allowed") }
                    else { Button("Allow…") { access.requestCapture() }.controlSize(.small) }
                }
                HStack {
                    Image(systemName: "hand.tap").foregroundStyle(AppColors.violet).frame(width: 24)
                    SectionHeading(title: "Accessibility", detail: "Activate the real status item when you click its image in the shelf.")
                    Spacer()
                    if access.canControl { StatusPill(title: "Allowed") }
                    else { Button("Allow…") { access.requestControl() }.controlSize(.small) }
                }
                HStack {
                    Text("If macOS asks to restart Barloom after granting access, restart it to finish setup.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Check access") { access.refresh() }.controlSize(.small)
                }
            }
        }.onAppear { access.refresh() }
    }
}
