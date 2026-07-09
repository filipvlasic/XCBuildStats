import Foundation

enum ManifestScanner {
    static let buildLogDomain: String = "Xcode.IDEActivityLogDomainType.BuildLog"

    static var overrideDerivedDataURL: URL?

    static var derivedDataURL: URL {
        if let override: URL = overrideDerivedDataURL {
            return override
        }
        let home: URL = FileManager.default.homeDirectoryForCurrentUser
        let defaultURL: URL = home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        guard let custom: String = UserDefaults(suiteName: "com.apple.dt.Xcode")?.string(forKey: "IDECustomDerivedDataLocation"),
              !custom.isEmpty else {
            return defaultURL
        }
        let expanded: String = (custom as NSString).expandingTildeInPath
        // A relative value is Xcode's workspace-relative setting and cannot be
        // resolved to one global folder; a consent-gated folder would make the
        // launch scan show a macOS permission prompt. Both fall back to default.
        guard expanded.hasPrefix("/"), !AppLocation.isConsentGated(path: expanded, home: home.path) else {
            return defaultURL
        }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    static func manifestURLs() -> [URL] {
        let fileManager: FileManager = .default
        let root: URL = derivedDataURL
        guard let entries: [URL] = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries.compactMap { directory in
            let manifest: URL = directory.appendingPathComponent("Logs/Build/LogStoreManifest.plist")
            return fileManager.fileExists(atPath: manifest.path) ? manifest : nil
        }
    }

    static func projectFolderNames() -> Set<String>? {
        let fileManager: FileManager = .default
        guard let entries: [URL] = try? fileManager.contentsOfDirectory(
            at: derivedDataURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        var names: Set<String> = []
        for entry in entries {
            let name: String = entry.lastPathComponent
            if name.range(of: "-[a-z]{28}$", options: .regularExpression) != nil {
                names.insert(name)
            }
        }
        return names
    }

    static func scan() -> [BuildRecord] {
        var records: [BuildRecord] = []
        let decoder: PropertyListDecoder = PropertyListDecoder()
        for url in manifestURLs() {
            guard let data: Data = try? Data(contentsOf: url),
                  let manifest: LogStoreManifest = try? decoder.decode(LogStoreManifest.self, from: data) else {
                continue
            }
            let project: String = projectName(from: url)
            for (_, log) in manifest.logs {
                guard log.domainType == buildLogDomain,
                      let id: String = log.uniqueIdentifier,
                      let start: Double = log.timeStartedRecording,
                      let stop: Double = log.timeStoppedRecording,
                      stop >= start else {
                    continue
                }
                let errors: Int = log.primaryObservable?.totalNumberOfErrors ?? 0
                let status: String? = log.primaryObservable?.highLevelStatus
                let succeeded: Bool = errors == 0 && status != "E"
                let record: BuildRecord = BuildRecord(
                    id: id,
                    project: project,
                    scheme: log.schemeName,
                    title: log.title,
                    started: Date(timeIntervalSinceReferenceDate: start),
                    stopped: Date(timeIntervalSinceReferenceDate: stop),
                    succeeded: succeeded,
                    errors: errors,
                    warnings: log.primaryObservable?.totalNumberOfWarnings ?? 0,
                    status: status
                )
                records.append(record)
            }
        }
        return records
    }

    static func projectName(from manifestURL: URL) -> String {
        let folder: String = manifestURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .lastPathComponent
        return stripDerivedDataHash(folder)
    }

    static func stripDerivedDataHash(_ name: String) -> String {
        if let range = name.range(of: "-[a-z]{28}$", options: .regularExpression) {
            return String(name[name.startIndex..<range.lowerBound])
        }
        return name
    }

    static func deletionEvents(previous: Set<String>, current: Set<String>, at date: Date) -> [BuildEvent] {
        let disappeared: Set<String> = previous.subtracting(current)
        return disappeared.map { folder in
            BuildEvent(
                id: "\(BuildEventType.derivedDataDeleted)|\(folder)|\(Int(date.timeIntervalSince1970))",
                type: BuildEventType.derivedDataDeleted,
                project: stripDerivedDataHash(folder),
                timestamp: date
            )
        }
    }
}
