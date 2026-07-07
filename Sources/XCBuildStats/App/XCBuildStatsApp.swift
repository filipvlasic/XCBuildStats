import SwiftUI
import AppKit

@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--report") {
            Reporter.runAndExit()
        }
        XCBuildStatsApp.main()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.applyDefaultIfNeeded()
        DispatchQueue.main.async {
            InstallerCleanup.offerIfNeeded()
        }
    }
}

struct XCBuildStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: DashboardViewModel = DashboardViewModel()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    let model: DashboardViewModel

    var body: some View {
        Text(model.menuBarSummary)
            .monospaced()
    }
}
