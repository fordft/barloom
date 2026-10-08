import CoreGraphics
import Testing
@testable import BarloomCore

@Suite("Notch-safe icon bar geometry")
struct MenuBarGeometryTests {
    @Test func spacerLengthCannotExceedAppKitLimit() {
        #expect(MenuBarGeometry.collapsedSpacerLength == 10_000)
        #expect(MenuBarGeometry.collapsedSpacerLength <= 10_000)
    }
    @Test func shelfAlwaysFitsBelowCameraHousing() {
        let screen = CGRect(x: 0, y: 0, width: 1_470, height: 956)
        let shelf = MenuBarGeometry.shelfFrame(screen: screen, menuBarHeight: 24, notchHeight: 38, anchorX: 950, desiredWidth: 600)
        #expect(shelf.maxY == screen.maxY - 38 - 6)
        #expect(shelf.minX >= screen.minX + 12)
        #expect(shelf.maxX <= screen.maxX - 12)
        #expect(shelf.height == 52)
    }

    @Test func aLongRowUsesTheScreenWidthRatherThanTheNotchGap() {
        let screen = CGRect(x: 0, y: 0, width: 1_470, height: 956)
        let shelf = MenuBarGeometry.shelfFrame(screen: screen, menuBarHeight: 38, notchHeight: 38, anchorX: 10, desiredWidth: 10_000)
        #expect(shelf.width == 1_446)
        #expect(shelf.minX == 12)
        #expect(shelf.maxY < 918)
    }

    @Test func placementHandlesDisplaysAboveAndLeftOfThePrimaryDisplay() {
        let screen = CGRect(x: -2_560, y: 956, width: 2_560, height: 1_440)
        let shelf = MenuBarGeometry.shelfFrame(screen: screen, menuBarHeight: 30, notchHeight: 0, anchorX: -1_700, desiredWidth: 800)
        #expect(screen.contains(shelf))
        #expect(shelf.maxY == 2_360)
        let quartz = MenuBarGeometry.quartzRect(fromAppKit: screen, primaryDisplayTop: 956)
        #expect(quartz.minY == -1_440)
        #expect(MenuBarGeometry.quartzRect(fromAppKit: quartz, primaryDisplayTop: 956) == screen)
    }

    @Test func statusRowUsesTheControlOnTheRequestedDisplay() {
        let windows = [
            MenuBarWindow(id: 1, ownerPID: 50, ownerName: "Barloom", title: "Barloom.Single.control",
                          frame: CGRect(x: 1_737, y: -1_502, width: 57, height: 30)),
            MenuBarWindow(id: 2, ownerPID: 50, ownerName: "Barloom", title: "com.barloom.app",
                          frame: CGRect(x: 4_297, y: -1_502, width: 57, height: 30)),
            MenuBarWindow(id: 3, ownerPID: 50, ownerName: "Barloom", title: "com.barloom.app",
                          frame: CGRect(x: 1_243, y: 0, width: 57, height: 33))
        ]
        #expect(MenuBarGeometry.statusRowTop(expected: -1_440, screenX: -594..<1_966,
                                             windows: windows, identifier: "com.barloom.app") == -1_502)
        #expect(MenuBarGeometry.statusRowTop(expected: 0, screenX: 0..<1_470,
                                             windows: windows, identifier: "com.barloom.app") == 0)
        #expect(MenuBarGeometry.statusRowTop(expected: 300, screenX: 0..<1_470,
                                             windows: windows, identifier: "com.barloom.app") == 300)
    }

    @Test func hiddenAndAlwaysHiddenSectionsStayDistinctWhileCollapsed() {
        let hidden = MenuBarDivider(windowID: 10, frame: CGRect(x: -19_000, y: 0, width: 20_000, height: 33), section: .hidden)
        let always = MenuBarDivider(windowID: 11, frame: CGRect(x: -39_400, y: 0, width: 20_000, height: 33), section: .alwaysHidden)
        let windows = [
            icon(1, x: -39_450), icon(2, x: -19_350), icon(3, x: -19_060), icon(4, x: 1_030),
            MenuBarWindow(id: 9, ownerPID: 50, ownerName: "Popover", title: "", frame: CGRect(x: -19_200, y: 0, width: 400, height: 510))
        ]
        #expect(MenuBarGeometry.icons(windows, between: [hidden, always], selectedDividerID: 10, section: .hidden).map(\.id) == [2, 3])
        #expect(MenuBarGeometry.icons(windows, between: [hidden, always], selectedDividerID: 10, section: .alwaysHidden).map(\.id) == [1])
        #expect(MenuBarGeometry.icons(windows, between: [hidden, always], selectedDividerID: 10, section: .all).map(\.id) == [1, 2, 3])
    }

    @Test func displayReplicasDoNotLeakIntoAnotherDisplaysBar() {
        let a = MenuBarDivider(windowID: 10, frame: CGRect(x: -19_000, y: 0, width: 20_000, height: 30), section: .hidden)
        let b = MenuBarDivider(windowID: 20, frame: CGRect(x: -16_440, y: 0, width: 20_000, height: 30), section: .hidden)
        let windows = [icon(1, x: -19_060), icon(2, x: -16_500), icon(3, x: -19_060, y: 1_440)]
        #expect(MenuBarGeometry.icons(windows, between: [a, b], selectedDividerID: 10, section: .hidden).map(\.id) == [1])
        #expect(MenuBarGeometry.icons(windows, between: [a, b], selectedDividerID: 20, section: .hidden).map(\.id) == [2])
    }

    @Test func controlWindowsAndOversizedSurfacesCannotBecomeIconCaptures() {
        let divider = MenuBarDivider(windowID: 10, frame: CGRect(x: -19_000, y: 0, width: 20_000, height: 33), section: .hidden)
        let windows = [icon(1, x: -19_060), icon(2, x: -19_120),
                       MenuBarWindow(id: 3, ownerPID: 50, ownerName: "Other", title: "", frame: CGRect(x: -19_200, y: 0, width: 32, height: 33), layer: 0)]
        #expect(MenuBarGeometry.icons(windows, between: [divider], selectedDividerID: 10, section: .hidden, excludedIDs: [2]).map(\.id) == [1])
        #expect(MenuBarGeometry.icons(windows, between: [], selectedDividerID: 10, section: .hidden).isEmpty)
        #expect(!MenuBarWindow(id: 4, ownerPID: 50, ownerName: "", title: "", frame: CGRect(x: 0, y: 0, width: 20_000, height: 33)).isIconSized)
    }

    private func icon(_ id: UInt32, x: CGFloat, y: CGFloat = 0) -> MenuBarWindow {
        MenuBarWindow(id: id, ownerPID: 50, ownerName: "Test", title: "icon", frame: CGRect(x: x, y: y, width: 32, height: 30))
    }
}
