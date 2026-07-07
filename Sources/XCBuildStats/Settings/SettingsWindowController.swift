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
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
