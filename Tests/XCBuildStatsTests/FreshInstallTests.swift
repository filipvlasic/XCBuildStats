import XCTest
@testable import XCBuildStats

/// End-to-end pipeline tests for a brand-new user: synthetic DerivedData on disk
/// → ManifestScanner.scan() → BuildStore ingest → Aggregator statistics.
final class FreshInstallTests: XCTestCase {
    private var root: URL!
    private let calendar: Calendar = {
        var calendar: Calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xcbs-fresh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        ManifestScanner.overrideDerivedDataURL = nil
        try? FileManager.default.removeItem(at: root)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func logEntry(
        id: String,
        title: String,
        start: Date,
        durationSeconds: Double,
        status: String = "S",
        errors: Int = 0,
        domain: String = "Xcode.IDEActivityLogDomainType.BuildLog"
    ) -> [String: Any] {
        return [
            "domainType": domain,
            "title": title,
            "uniqueIdentifier": id,
            "fileName": "\(id).xcactivitylog",
            "timeStartedRecording": start.timeIntervalSinceReferenceDate,
            "timeStoppedRecording": start.timeIntervalSinceReferenceDate + durationSeconds,
            "schemeIdentifier-schemeName": "Scheme",
            "primaryObservable": [
                "highLevelStatus": status,
                "totalNumberOfErrors": errors,
                "totalNumberOfWarnings": 0
            ]
        ]
    }

    private func writeActivityLog(project: String, hash: String = "abcdefghijklmnopqrstuvwxyzab", id: String, statusLine: String) throws {
        let buildDir: URL = root.appendingPathComponent("\(project)-\(hash)/Logs/Build", isDirectory: true)
        let plain: URL = buildDir.appendingPathComponent("\(id).plain")
        try Data(#"0#---36"\#(UUID().uuidString)\#(statusLine)-0("#.utf8).write(to: plain)
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-c", plain.path]
        let pipe: Pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data: Data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try data.write(to: buildDir.appendingPathComponent("\(id).xcactivitylog"))
    }

    private func writeManifest(project: String, hash: String = "abcdefghijklmnopqrstuvwxyzab", logs: [[String: Any]]) throws {
        let buildDir: URL = root
            .appendingPathComponent("\(project)-\(hash)/Logs/Build", isDirectory: true)
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        var keyed: [String: Any] = [:]
        for log in logs {
            keyed[log["uniqueIdentifier"] as! String] = log
        }
        let data: Data = try PropertyListSerialization.data(
            fromPropertyList: ["logs": keyed], format: .xml, options: 0
        )
        try data.write(to: buildDir.appendingPathComponent("LogStoreManifest.plist"))
    }

    private func tempStore() -> BuildStore {
        return BuildStore(path: root.appendingPathComponent("db.sqlite").path)
    }

    func testFreshUserWithExistingDerivedDataHistory() throws {
        let day: Date = date(2026, 7, 8, 0)
        try writeManifest(project: "MyApp", logs: [
            logEntry(id: "b1", title: "Build MyApp", start: date(2026, 7, 8, 9), durationSeconds: 120, status: "S"),
            logEntry(id: "b2", title: "Build MyApp", start: date(2026, 7, 8, 9, 30), durationSeconds: 60, status: "W"),
            logEntry(id: "b3", title: "Build MyApp", start: date(2026, 7, 8, 11), durationSeconds: 30, status: "E", errors: 2),
            logEntry(id: "c1", title: "Clean MyApp", start: date(2026, 7, 8, 8), durationSeconds: 10, status: "S")
        ])
        try writeManifest(project: "Tool", hash: "zyxwvutsrqponmlkjihgfedcbazy", logs: [
            logEntry(id: "t1", title: "Build Tool", start: date(2026, 7, 8, 14), durationSeconds: 45, status: "S")
        ])
        ManifestScanner.overrideDerivedDataURL = root

        let scanned: [BuildRecord] = ManifestScanner.scan()
        XCTAssertEqual(scanned.count, 5)
        let b1: BuildRecord = try XCTUnwrap(scanned.first { $0.id == "b1" })
        XCTAssertEqual(b1.started, date(2026, 7, 8, 9), "Cocoa reference date must convert exactly")
        XCTAssertEqual(b1.duration, 120)
        XCTAssertEqual(b1.project, "MyApp", "DerivedData hash must be stripped")
        XCTAssertTrue(try XCTUnwrap(scanned.first { $0.id == "b2" }).succeeded, "W (warnings) is a successful build")
        XCTAssertFalse(try XCTUnwrap(scanned.first { $0.id == "b3" }).succeeded)
        XCTAssertTrue(try XCTUnwrap(scanned.first { $0.id == "c1" }).isClean)

        let store: BuildStore = tempStore()
        XCTAssertEqual(store.ingest(scanned).count, 5)
        XCTAssertEqual(store.ingest(ManifestScanner.scan()).count, 0, "relaunch rescan must not duplicate anything")

        let all: [BuildRecord] = store.allBuilds()
        let builds: [BuildRecord] = all.filter { !$0.isClean }
        let cleans: [BuildRecord] = all.filter { $0.isClean }
        let period: DateInterval = Aggregator.periodInterval(grouping: .day, anchor: day, calendar: calendar)

        let summary: PeriodSummary = Aggregator.summary(builds, in: period)
        XCTAssertEqual(summary.totalDuration, 255, "120 + 60 + 30 + 45")
        XCTAssertEqual(summary.count, 4)
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(summary.successRate, 0.75, accuracy: 0.0001)
        XCTAssertEqual(summary.averageDuration, 63.75, accuracy: 0.0001)
        XCTAssertEqual(Aggregator.builds(builds, in: period).max { $0.duration < $1.duration }?.id, "b1", "longest build")
        XCTAssertEqual(Aggregator.builds(cleans, in: period).reduce(0) { $0 + $1.duration }, 10)

        let stats: [ProjectStat] = Aggregator.projectStats(builds, in: period)
        XCTAssertEqual(stats.map { $0.project }, ["MyApp", "Tool"])
        XCTAssertEqual(stats.first?.totalDuration, 210)
        XCTAssertEqual(stats.first?.count, 3)

        let bars: [Bar] = Aggregator.bars(builds, in: period, subComponent: .hour, calendar: calendar)
        XCTAssertEqual(bars.count, 3, "hours 09, 11, 14")
        XCTAssertEqual(bars.reduce(0) { $0 + $1.minutes }, 255.0 / 60.0, accuracy: 0.0001, "chart must sum to the same total as the headline")
    }

    func testLintErrorsDoNotFailACompletedBuild() throws {
        try writeManifest(project: "Linty", logs: [
            logEntry(id: "lint-ok", title: "Build Linty", start: date(2026, 7, 8, 9), durationSeconds: 60, status: "E", errors: 2),
            logEntry(id: "real-fail", title: "Build Linty", start: date(2026, 7, 8, 10), durationSeconds: 30, status: "E", errors: 1)
        ])
        try writeActivityLog(project: "Linty", id: "lint-ok", statusLine: #"26"Build finished with errors"#)
        try writeActivityLog(project: "Linty", id: "real-fail", statusLine: #"12"Build failed"#)
        ManifestScanner.overrideDerivedDataURL = root

        let scanned: [BuildRecord] = ManifestScanner.scan()
        XCTAssertTrue(try XCTUnwrap(scanned.first { $0.id == "lint-ok" }).succeeded, "completed build with lint error diagnostics is a success")
        XCTAssertFalse(try XCTUnwrap(scanned.first { $0.id == "real-fail" }).succeeded)

        // A row stored as failed by an older version heals on the next scan.
        let store: BuildStore = tempStore()
        let asFailed: [BuildRecord] = scanned.map { record in
            BuildRecord(
                id: record.id, project: record.project, scheme: record.scheme, title: record.title,
                started: record.started, stopped: record.stopped,
                succeeded: false, errors: record.errors, warnings: record.warnings, status: record.status
            )
        }
        store.ingest(asFailed)
        XCTAssertEqual(store.reconcileOutcomes(scanned), 1, "only the lint build flips to succeeded")
        XCTAssertEqual(store.allBuilds().first { $0.id == "lint-ok" }?.succeeded, true)
        XCTAssertEqual(store.reconcileOutcomes(scanned), 0, "second pass is a no-op")
    }

    func testFreshUserWithoutDerivedData() {
        ManifestScanner.overrideDerivedDataURL = root.appendingPathComponent("does-not-exist")

        XCTAssertEqual(ManifestScanner.scan().count, 0)
        XCTAssertEqual(ManifestScanner.manifestURLs().count, 0)
        XCTAssertNil(ManifestScanner.projectFolderNames(), "unreadable directory must be nil, not a mass-deletion signal")

        let store: BuildStore = tempStore()
        XCTAssertEqual(store.ingest(ManifestScanner.scan()).count, 0)
        XCTAssertEqual(store.allBuilds().count, 0)

        let period: DateInterval = Aggregator.periodInterval(grouping: .day, anchor: Date(timeIntervalSinceReferenceDate: 0), calendar: calendar)
        let summary: PeriodSummary = Aggregator.summary([], in: period)
        XCTAssertEqual(summary.totalDuration, 0)
        XCTAssertEqual(summary.count, 0)
        XCTAssertEqual(summary.successRate, 0)
        XCTAssertEqual(summary.averageDuration, 0)
        XCTAssertNil(Aggregator.previousPeriodDelta([], grouping: .day, now: Date(timeIntervalSinceReferenceDate: 0), offset: 0, calendar: calendar))
    }

    func testEmptyDerivedDataDirectory() {
        ManifestScanner.overrideDerivedDataURL = root
        XCTAssertEqual(ManifestScanner.scan().count, 0)
        XCTAssertEqual(ManifestScanner.projectFolderNames(), [], "existing but empty directory is an empty set, not nil")
    }

    func testCorruptAndPartialManifestsAreSkipped() throws {
        try writeManifest(project: "Good", logs: [
            logEntry(id: "ok", title: "Build Good", start: date(2026, 7, 8, 9), durationSeconds: 60),
            {
                var running: [String: Any] = logEntry(id: "running", title: "Build Good", start: date(2026, 7, 8, 10), durationSeconds: 0)
                running.removeValue(forKey: "timeStoppedRecording")
                return running
            }(),
            {
                var negative: [String: Any] = logEntry(id: "negative", title: "Build Good", start: date(2026, 7, 8, 11), durationSeconds: 0)
                negative["timeStoppedRecording"] = (negative["timeStartedRecording"] as! Double) - 5
                return negative
            }(),
            logEntry(id: "other", title: "Log Good", start: date(2026, 7, 8, 12), durationSeconds: 30, domain: "Xcode.IDEActivityLogDomainType.DebugSession")
        ])
        let corruptDir: URL = root.appendingPathComponent("Broken-abcdefghijklmnopqrstuvwxyzab/Logs/Build", isDirectory: true)
        try FileManager.default.createDirectory(at: corruptDir, withIntermediateDirectories: true)
        try Data("not a plist".utf8).write(to: corruptDir.appendingPathComponent("LogStoreManifest.plist"))
        ManifestScanner.overrideDerivedDataURL = root

        let scanned: [BuildRecord] = ManifestScanner.scan()
        XCTAssertEqual(scanned.map { $0.id }, ["ok"], "running, negative-duration, non-build, and corrupt entries are all skipped")
    }

    func testWatcherOnMissingPathDoesNotCrash() {
        let missing: String = root.appendingPathComponent("nope/DerivedData").path
        let watcher: DerivedDataWatcher = DerivedDataWatcher(path: missing) {}
        watcher.start()
        watcher.stop()
    }
}
