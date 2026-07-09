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

    /// Folders where the first file access makes macOS show a consent prompt
    /// ("XCBuildStats would like to access files in your Downloads folder").
    /// Background scans must never reach into these uninvited.
    static func isConsentGated(path: String, home: String) -> Bool {
        let normalizedPath: String = URL(fileURLWithPath: path).standardizedFileURL.path
        let normalizedHome: String = home.hasSuffix("/") ? String(home.dropLast()) : home
        let gated: [String] = [
            "Desktop",
            "Documents",
            "Downloads",
            "Library/Mobile Documents",
            "Library/CloudStorage"
        ]
        return gated.contains { folder in
            let root: String = "\(normalizedHome)/\(folder)"
            return normalizedPath == root || normalizedPath.hasPrefix("\(root)/")
        }
    }
}
