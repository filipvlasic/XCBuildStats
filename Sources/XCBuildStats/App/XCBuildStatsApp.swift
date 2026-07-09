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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim: Bool = false

    var body: some View {
        Text(model.menuBarSummary)
            .monospaced()
            .scaleEffect(dim ? 0.92 : 1.0)
            .opacity(dim ? 0.45 : 1.0)
            .onChange(of: model.menuBarSummary) { _, _ in
                guard Preferences.shared.pulseMenuBar,
                      !Preferences.shared.disableAnimations,
                      !reduceMotion else {
                    return
                }
                withAnimation(.easeOut(duration: 0.12)) {
                    dim = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        dim = false
                    }
                }
            }
    }
}
