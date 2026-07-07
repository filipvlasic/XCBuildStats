import Foundation
import ServiceManagement

enum LoginItem {
    /// SMAppService.mainApp only works from a real .app bundle (with CFBundleIdentifier).
    /// Running via `swift run` produces a bare executable where register() would throw.
    static var isSupported: Bool {
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundlePath.hasSuffix(".app") else {
            return false
        }
        // A login item pointing into a mounted disk image is useless (it isn't
        // mounted at login), so only support it once the app runs from a real location.
        return !Bundle.main.bundlePath.hasPrefix("/Volumes/")
    }

    static var isEnabled: Bool {
        guard isSupported else {
            return false
        }
        return SMAppService.mainApp.status == .enabled
    }

    /// Enables the login item once on first launch (of the packaged app), then
    /// respects the user's later choice.
    static func applyDefaultIfNeeded() {
        guard isSupported else {
            return
        }
        let key: String = "didApplyDefaultLoginItem"
        let defaults: UserDefaults = .standard
        guard !defaults.bool(forKey: key) else {
            return
        }
        let status: SMAppService.Status = SMAppService.mainApp.status
        if status == .enabled || status == .requiresApproval {
            defaults.set(true, forKey: key)
            return
        }
        do {
            try SMAppService.mainApp.register()
            defaults.set(true, forKey: key)
        } catch {
            NSLog("XCBuildStats: default login item registration failed: \(error.localizedDescription)")
            // Leave the flag unset so the default is retried on the next launch.
        }
    }

    static func setEnabled(_ enabled: Bool) {
        guard isSupported else {
            return
        }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("XCBuildStats: login item update failed: \(error.localizedDescription)")
        }
    }
}
