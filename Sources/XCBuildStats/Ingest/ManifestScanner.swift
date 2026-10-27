import Compression
import Foundation

enum ManifestScanner {
    static let buildLogDomain: String = "Xcode.IDEActivityLogDomainType.BuildLog"

    private static var activityLogResultCache: [String: Bool?] = [:]
    private static let activityLogResultCacheLock: NSLock = NSLock()

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
        return manifestURLs(in: derivedDataURL)
    }

    static func manifestURLs(in root: URL) -> [URL] {
        let fileManager: FileManager = .default
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

    /// The workspace or project a DerivedData folder belongs to, from the
    /// info.plist Xcode keeps next to its logs.
    static func workspacePath(ofDerivedDataFolder folder: URL) -> String? {
        let url: URL = folder.appendingPathComponent("info.plist")
        guard let data: Data = try? Data(contentsOf: url),
              let plist: [String: Any] = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return plist["WorkspacePath"] as? String
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
        return manifestURLs().flatMap { url in
            records(inManifestAt: url, project: projectName(from: url))
        }
    }

    static func records(inManifestAt url: URL, project: String) -> [BuildRecord] {
        guard let data: Data = try? Data(contentsOf: url),
              let manifest: LogStoreManifest = try? PropertyListDecoder().decode(LogStoreManifest.self, from: data) else {
            return []
        }
        var records: [BuildRecord] = []
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
            var succeeded: Bool = errors == 0 && status != "E"
            // Lint/script phases can emit error-level diagnostics without
            // failing the build; the manifest counters can't tell those
            // apart, but the activity log records the real outcome.
            if !succeeded, let fileName: String = log.fileName {
                let logURL: URL = url.deletingLastPathComponent().appendingPathComponent(fileName)
                if let realOutcome: Bool = activityLogResult(id: id, at: logURL) {
                    succeeded = realOutcome
                }
            }
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
                status: status,
                source: BuildSource.from(className: log.className, title: log.title)
            )
            records.append(record)
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

    /// Reads the real outcome from the activity log's status string — the manifest
    /// counters can't distinguish a genuinely failed build from one that finished
    /// while lint/script phases emitted error-level diagnostics. The status is an
    /// SLF length-prefixed string, so the prefix is part of the match:
    ///   `15"Build succeeded`, `26"Build finished with errors` → built
    ///   `12"Build failed` → really failed
    /// Unknown/missing status falls back to the counter classification (nil).
    static func activityLogResult(id: String, at url: URL) -> Bool? {
        activityLogResultCacheLock.lock()
        if let cached: Bool? = activityLogResultCache[id] {
            activityLogResultCacheLock.unlock()
            return cached
        }
        activityLogResultCacheLock.unlock()
        guard let compressed: Data = try? Data(contentsOf: url), let raw: Data = gunzip(compressed) else {
            // Not cached: the log may simply not be fully written yet.
            return nil
        }
        let result: Bool?
        if raw.range(of: Data("12\"Build failed".utf8)) != nil {
            result = false
        } else if raw.range(of: Data("15\"Build succeeded".utf8)) != nil
            || raw.range(of: Data("26\"Build finished with errors".utf8)) != nil {
            result = true
        } else {
            result = nil
        }
        activityLogResultCacheLock.lock()
        activityLogResultCache[id] = result
        activityLogResultCacheLock.unlock()
        return result
    }

    static func gunzip(_ data: Data) -> Data? {
        let bytes: [UInt8] = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else {
            return nil
        }
        let flags: UInt8 = bytes[3]
        var offset: Int = 10
        if flags & 0x04 != 0 {
            guard bytes.count > offset + 1 else {
                return nil
            }
            offset += 2 + (Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8))
        }
        if flags & 0x08 != 0 {
            while offset < bytes.count, bytes[offset] != 0 {
                offset += 1
            }
            offset += 1
        }
        if flags & 0x10 != 0 {
            while offset < bytes.count, bytes[offset] != 0 {
                offset += 1
            }
            offset += 1
        }
        if flags & 0x02 != 0 {
            offset += 2
        }
        guard offset < bytes.count - 8 else {
            return nil
        }
        return inflateRawDeflate(bytes, from: offset, to: bytes.count - 8)
    }

    private static func inflateRawDeflate(_ bytes: [UInt8], from start: Int, to end: Int) -> Data? {
        let chunkSize: Int = 1 << 20
        let chunk: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer {
            chunk.deallocate()
        }
        var stream: compression_stream = compression_stream(
            dst_ptr: chunk, dst_size: 0, src_ptr: chunk, src_size: 0, state: nil
        )
        var status: compression_status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard status == COMPRESSION_STATUS_OK else {
            return nil
        }
        defer {
            compression_stream_destroy(&stream)
        }
        var output: Data = Data()
        bytes.withUnsafeBufferPointer { buffer in
            stream.src_ptr = buffer.baseAddress! + start
            stream.src_size = end - start
            repeat {
                stream.dst_ptr = chunk
                stream.dst_size = chunkSize
                status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced: Int = chunkSize - stream.dst_size
                if produced > 0 {
                    output.append(chunk, count: produced)
                }
            } while status == COMPRESSION_STATUS_OK
        }
        return status == COMPRESSION_STATUS_END ? output : nil
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
