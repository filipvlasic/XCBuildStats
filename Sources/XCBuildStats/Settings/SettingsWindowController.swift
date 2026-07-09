import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared: SettingsWindowController = SettingsWindowController()

    private var window: NSWindow?

    func show(model: DashboardViewModel) {
        if window == nil {
            let view: SettingsView = SettingsView(preferences: Preferences.shared, model: model)
            let hosting: NSHostingController<SettingsView> = NSHostingController(rootView: view)
            let window: NSWindow = NSWindow(contentViewController: hosting)
            window.title = "XCBuildStats Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace]
            window.center()
            self.window = window
        }
        guard let window else {
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
