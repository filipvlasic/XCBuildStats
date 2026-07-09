import Foundation
import ServiceManagement

enum LoginItem {
    private static let userDisabledKey: String = "loginItemUserDisabled"
    private static let defaults: UserDefaults = .standard

    /// SMAppService.mainApp only works from a real .app bundle (with CFBundleIdentifier).
    /// Running via `swift run` produces a bare executable where register() would throw.
    /// Ephemeral locations (mounted DMG, App Translocation) are excluded because a
    /// login item registered there points at a path that is gone by the next login.
    static var isSupported: Bool {
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundlePath.hasSuffix(".app") else {
            return false
        }
        return !AppLocation.isEphemeral
    }

    static var isEnabled: Bool {
        guard isSupported else {
            return false
        }
        return SMAppService.mainApp.status == .enabled
    }

    /// Launch at login is on by default for everyone. This runs on every launch and
    /// re-registers the login item whenever the registration is missing — which macOS
    /// does each time the app is updated in place, since the registration is tied to the
    /// app's code signature. The only thing that stops it is the user explicitly turning
    /// the toggle off (recorded in `userDisabledKey`).
    static func applyDefaultIfNeeded() {
        guard isSupported, shouldRegisterByDefault(status: SMAppService.mainApp.status, userDisabled: defaults.bool(forKey: userDisabledKey)) else {
            return
        }
        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("XCBuildStats: default login item registration failed: \(error.localizedDescription)")
            // Retried on the next launch, since the status stays unregistered.
        }
    }

    static func shouldRegisterByDefault(status: SMAppService.Status, userDisabled: Bool) -> Bool {
        guard !userDisabled else {
            return false
        }
        switch status {
        case .enabled, .requiresApproval:
            return false
        default:
            return true
        }
    }

    static func setEnabled(_ enabled: Bool) {
        guard isSupported else {
            return
        }
        defaults.set(!enabled, forKey: userDisabledKey)
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
