import Foundation

enum AppLocation {
    /// True while the app runs from a location that disappears after reboot/eject:
    /// a mounted disk image, or the randomized path Gatekeeper App Translocation
    /// uses when a quarantined app is launched straight from a DMG or Downloads.
    static var isEphemeral: Bool {
        return isEphemeral(bundlePath: Bundle.main.bundlePath)
    }

    static func isEphemeral(bundlePath: String) -> Bool {
        return bundlePath.hasPrefix("/Volumes/") || bundlePath.contains("/AppTranslocation/")
    }
}
