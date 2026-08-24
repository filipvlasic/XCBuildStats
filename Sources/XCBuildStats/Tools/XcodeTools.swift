import AppKit
import Foundation

enum XcodeTools {
    static let xcodeBundleId: String = "com.apple.dt.Xcode"

    static var defaultPackageCacheURL: URL {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/org.swift.swiftpm", isDirectory: true)
    }

    /// Deletes everything inside DerivedData but keeps the folder itself, so the
    /// FSEvents watcher keeps a valid root and Xcode recreates content in place.
    @discardableResult
    static func deleteDerivedDataContents(at root: URL = ManifestScanner.derivedDataURL) -> Bool {
        guard let entries: [URL] = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil),
              !entries.isEmpty else {
            return false
        }
        return purge(entries)
    }

    /// Equivalent of Xcode's "Reset Package Caches": the global SwiftPM repository
    /// cache plus every project's SourcePackages checkouts inside DerivedData.
    @discardableResult
    static func resetPackageCaches(
        cache: URL = defaultPackageCacheURL,
        derivedData: URL = ManifestScanner.derivedDataURL
    ) -> Bool {
        let fileManager: FileManager = .default
        var targets: [URL] = []
        if fileManager.fileExists(atPath: cache.path) {
            targets.append(cache)
        }
        let projects: [URL] = (try? fileManager.contentsOfDirectory(at: derivedData, includingPropertiesForKeys: nil)) ?? []
        for project in projects {
            let sourcePackages: URL = project.appendingPathComponent("SourcePackages", isDirectory: true)
            if fileManager.fileExists(atPath: sourcePackages.path) {
                targets.append(sourcePackages)
            }
        }
        guard !targets.isEmpty else {
            return false
        }
        return purge(targets)
    }

    /// Instantly moves items to a temp staging folder (same-volume rename works in
    /// one visible moment, even for files another process holds open), then
    /// reclaims the disk space in the background. Falls back to in-place removal.
    private static func purge(_ items: [URL]) -> Bool {
        let fileManager: FileManager = .default
        let staging: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xcbuildstats-purge-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        var allRemoved: Bool = true
        for (index, item) in items.enumerated() {
            do {
                try fileManager.moveItem(at: item, to: staging.appendingPathComponent("\(index)-\(item.lastPathComponent)"))
            } catch {
                do {
                    try fileManager.removeItem(at: item)
                } catch {
                    allRemoved = false
                }
            }
        }
        DispatchQueue.global(qos: .utility).async {
            try? fileManager.removeItem(at: staging)
        }
        return allRemoved
    }

    static var isXcodeRunning: Bool {
        return !NSRunningApplication.runningApplications(withBundleIdentifier: xcodeBundleId).isEmpty
    }

    @discardableResult
    static func forceQuitXcode() -> Bool {
        let running: [NSRunningApplication] = NSRunningApplication.runningApplications(withBundleIdentifier: xcodeBundleId)
        guard !running.isEmpty else {
            return false
        }
        // Remember which Xcode this was, so Launch/Clean restart reopens the
        // same version on machines with several Xcodes installed.
        if let path: String = running.first?.bundleURL?.path {
            UserDefaults.standard.set(path, forKey: lastXcodeKey)
        }
        var quit: Bool = false
        for app in running where app.forceTerminate() {
            quit = true
        }
        return quit
    }

    /// Preference order: the Xcode we last quit → the `xcode-select`ed Xcode →
    /// the system default for Xcode's bundle id.
    static func xcodeAppURL() -> URL? {
        let remembered: String? = UserDefaults.standard.string(forKey: lastXcodeKey)
        let developerDir: String? = try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link")
        if let path: String = resolveXcodeAppPath(remembered: remembered, developerDir: developerDir, exists: { FileManager.default.fileExists(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: xcodeBundleId)
    }

    static func resolveXcodeAppPath(remembered: String?, developerDir: String?, exists: (String) -> Bool) -> String? {
        if let remembered, exists(remembered) {
            return remembered
        }
        // "/Applications/Xcode26_0.app/Contents/Developer" → "/Applications/Xcode26_0.app";
        // a CommandLineTools selection has no ".app" and falls through.
        if let developerDir, let range = developerDir.range(of: ".app/") {
            let appPath: String = String(developerDir[..<range.lowerBound]) + ".app"
            if exists(appPath) {
                return appPath
            }
        }
        return nil
    }

    @discardableResult
    static func launchXcode() -> Bool {
        guard let url: URL = xcodeAppURL() else {
            return false
        }
        let semaphore: DispatchSemaphore = DispatchSemaphore(value: 0)
        var launched: Bool = false
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { application, _ in
            launched = application != nil
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 15)
        return launched
    }

    /// The whole ritual in one go: quit Xcode, wipe DerivedData, relaunch the
    /// same Xcode (which restores the last open workspace itself).
    @discardableResult
    static func cleanRestart() -> Bool {
        if isXcodeRunning {
            guard forceQuitXcode(), waitForXcodeTermination() else {
                return false
            }
        }
        deleteDerivedDataContents()
        return launchXcode()
    }

    static func waitForXcodeTermination(timeout: TimeInterval = 10) -> Bool {
        let deadline: Date = Date().addingTimeInterval(timeout)
        while isXcodeRunning {
            guard Date() < deadline else {
                return false
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return true
    }

    private static let lastXcodeKey: String = "lastXcodeAppPath"
}
