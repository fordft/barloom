import AppKit
import BarloomCore
import Combine
import CoreGraphics
import SwiftUI

struct LibraryMenuBarIcon: Identifiable {
    var id: UInt32 { captured.id }
    let key: String
    let name: String
    let captured: CapturedMenuBarIcon
}

@MainActor
final class MenuBarLibrary: ObservableObject {
    @Published private(set) var icons: [LibraryMenuBarIcon] = []
    @Published private(set) var defaultHiddenKeys: Set<String> = []
    @Published private(set) var isLoading = false
    @Published var notice: String?
    private let catalog = MenuBarCatalog()
    private var keys: [UInt32: String] = [:]

    func refresh(on requestedScreen: NSScreen? = nil) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard CGPreflightScreenCaptureAccess() else {
            notice = "Allow Screen Recording below to see and choose your actual menu bar icons."
            return
        }
        guard let screen = requestedScreen ?? NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let top = MenuBarDisplay.primaryDisplayTop
        let all = await catalog.windows()
        let rowTop = MenuBarDisplay.statusRowTop(on: screen, windows: all, primaryDisplayTop: top)
        let identifier = Bundle.main.bundleIdentifier ?? "com.barloom.app"
        let row = all.filter { abs($0.frame.minY - rowTop) < 8 }
        let own = row.filter { $0.title == identifier || $0.title.hasPrefix("Barloom.") }
        guard let control = own.filter({
            $0.isIconSized && screen.frame.minX <= $0.frame.midX && $0.frame.midX < screen.frame.maxX
        }).min(by: {
            ($0.title.hasSuffix(".control") ? 0 : 1, abs($0.frame.maxX - screen.frame.maxX)) <
            ($1.title.hasSuffix(".control") ? 0 : 1, abs($1.frame.maxX - screen.frame.maxX))
        }), let hidden = own.filter({
            $0.frame.width >= 1_000 && $0.frame.maxX <= control.frame.minX + 2
        }).max(by: { $0.frame.maxX < $1.frame.maxX }) else {
            icons = []
            notice = "Could not locate Barloom’s hidden section on this display."
            return
        }
        let dividers = own.filter { $0.frame.width >= 1_000 }.map {
            MenuBarDivider(windowID: $0.id, frame: $0.frame, section: .hidden)
        }
        let hiddenIcons = MenuBarGeometry.icons(row, between: dividers, selectedDividerID: hidden.id,
                                                section: .hidden, excludedIDs: Set(own.map(\.id)))
        let visibleIcons = row.filter {
            $0.isIconSized && $0.frame.minX >= hidden.frame.maxX - 2 &&
            $0.frame.maxX <= control.frame.minX + 2 &&
            $0.ownerPID != getpid() && $0.title != identifier && !$0.title.hasPrefix("Barloom.")
        }
        let windows = Array(Dictionary(uniqueKeysWithValues: (hiddenIcons + visibleIcons).map { ($0.id, $0) }).values)
            .sorted { $0.frame.minX < $1.frame.minX }
        let captured = await catalog.capture(windows)
        let running = NSWorkspace.shared.runningApplications
        var ordinal: [String: Int] = [:]
        icons = captured.map { image in
            let window = image.window
            let namespace = window.title.isEmpty ? window.ownerName : window.title
            let index = ordinal[namespace, default: 0]
            ordinal[namespace] = index + 1
            let key = keys[window.id] ?? "\(namespace)|\(index)"
            keys[window.id] = key
            let name = running.first { $0.bundleIdentifier == window.title }?.localizedName ?? (window.title.isEmpty ? window.ownerName : window.title)
            return LibraryMenuBarIcon(key: key, name: name, captured: image)
        }
        let hiddenIDs = Set(hiddenIcons.map(\.id))
        defaultHiddenKeys = Set(icons.filter { hiddenIDs.contains($0.id) }.map(\.key))
        notice = icons.isEmpty ? "No menu bar icons were available on this display. Try refreshing." : nil
    }
}

struct MenuBarLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var library: MenuBarLibrary
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    SectionHeading(title: "Choose icons for Barloom", detail: "Manage your icons here. Checked icons appear in the bar below Barloom’s button.")
                    Spacer()
                    Button { Task { await library.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(library.isLoading).help("Refresh menu bar icons")
                }
                if library.isLoading { ProgressView().controlSize(.small) }
                if let notice = library.notice { Text(notice).font(.system(size: 11)).foregroundStyle(.secondary) }
                LazyVGrid(columns: [.init(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                    ForEach(library.icons) { icon in
                        HStack(spacing: 10) {
                            if let image = icon.captured.png.flatMap(NSImage.init(data:)) {
                                Image(nsImage: image).resizable().scaledToFit().frame(width: 40, height: 28)
                            } else { Image(systemName: "app.dashed").frame(width: 40, height: 28) }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(icon.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                Text(model.isMenuBarIconIncluded(icon) ? "In Barloom" : "Not selected")
                                    .font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 2)
                            Toggle("Put \(icon.name) in Barloom", isOn: Binding(get: {
                                model.isMenuBarIconIncluded(icon)
                            }, set: { enabled in model.setMenuBarIcon(icon, included: enabled) }))
                                .labelsHidden().toggleStyle(.checkbox)
                        }.padding(11).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                Text("Click Barloom’s menu bar icon to open selected icons. Right-click it to open all hidden icons. macOS may keep some selected icons visible in the main bar.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.task { await library.refresh() }
    }
}
