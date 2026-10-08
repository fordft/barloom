import Foundation
import AppKit
import CoreGraphics
import Testing
@testable import Barloom
import BarloomCore

@Suite("Menu bar presentation", .serialized)
@MainActor
struct PresentationTests {
    @Test func clickingTheBarDoesNotEnterArrangementMode() throws {
        let (model, defaults, name) = try makeModel()
        defer { defaults.removePersistentDomain(forName: name) }
        model.preferences.menuBarEnabled = true
        let monitoringSettings = model.preferences
        #expect(model.overflowSection == nil)
        model.toggleHidden()
        #expect(model.overflowSection == .hidden)
        #expect(!model.isArrangingMenuBar)
        model.toggleHidden()
        #expect(model.overflowSection == nil)
        #expect(model.preferences == monitoringSettings)
    }

    @Test func onlyExplicitArrangeModeRevealsTheMainBar() throws {
        let (model, defaults, name) = try makeModel()
        defer { defaults.removePersistentDomain(forName: name) }
        model.preferences.menuBarEnabled = true
        model.toggleMenuBarArrangement()
        #expect(model.isArrangingMenuBar)
        #expect(model.overflowSection == nil)
        model.toggleHidden()
        #expect(!model.isArrangingMenuBar)
        #expect(model.overflowSection == .hidden)
        model.preferences.menuBarEnabled = false
        #expect(model.overflowSection == nil)
        #expect(!model.isArrangingMenuBar)
    }

    @Test func alwaysHiddenSelectionAndClosingPreserveModuleSettings() throws {
        let (model, defaults, name) = try makeModel()
        defer { defaults.removePersistentDomain(forName: name) }
        model.preferences.menuBarEnabled = true
        model.preferences.alwaysHiddenEnabled = true
        model.toggleAlwaysHidden()
        #expect(model.overflowSection == .alwaysHidden)
        model.revealAll()
        #expect(model.overflowSection == .all)
        model.closeIconShelf()
        #expect(model.overflowSection == nil)
        #expect(model.preferences.statsEnabled)
        #expect(model.preferences.runnerEnabled)
        #expect(model.preferences.portsEnabled)
    }

    @Test func offscreenClickEventsCarryTheValidatedWindowNumber() throws {
        let item = MenuBarWindow(id: 123_456, ownerPID: 999, ownerName: "Test", title: "", frame: CGRect(x: -20_100, y: 0, width: 32, height: 30))
        let payloads = MenuBarActivation.clickEventData(for: item, rightClick: false)
        #expect(payloads.count == 2)
        let event = try #require(CGEvent(withDataAllocator: nil, data: payloads[0] as CFData))
        #expect(NSEvent(cgEvent: event)?.windowNumber == Int(item.id))
        #expect(event.location == CGPoint(x: -20_084, y: 15))
    }

    private func makeModel() throws -> (AppModel, UserDefaults, String) {
        let name = "com.barloom.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return (AppModel(defaults: defaults), defaults, name)
    }
}
