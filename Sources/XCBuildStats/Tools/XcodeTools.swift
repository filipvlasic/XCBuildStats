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
        var quit: Bool = false
        for app in running where app.forceTerminate() {
            quit = true
        }
        return quit
    }
}
