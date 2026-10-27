import XCTest
import SQLite3
@testable import XCBuildStats

/// Builds run with `xcodebuild` outside Xcode (AI agents, scripts): source
/// classification, argv parsing, log-store correlation, storage and aggregation.
final class CommandLineBuildTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xcbs-cli-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        ManifestScanner.overrideDerivedDataURL = nil
        try? FileManager.default.removeItem(at: root)
    }

    private func invocation(_ arguments: [String], in directory: String? = "/work/app") -> XcodebuildInvocation {
        return XcodebuildInvocation(arguments: arguments, workingDirectory: directory)
    }

    private func logEntry(id: String, title: String, className: String?, start: Date, seconds: Double, status: String = "S") -> [String: Any] {
        var entry: [String: Any] = [
            "domainType": ManifestScanner.buildLogDomain,
            "title": title,
            "uniqueIdentifier": id,
            "timeStartedRecording": start.timeIntervalSinceReferenceDate,
            "timeStoppedRecording": start.timeIntervalSinceReferenceDate + seconds,
            "schemeIdentifier-schemeName": "App",
            "primaryObservable": [
                "highLevelStatus": status,
                "totalNumberOfErrors": status == "E" ? 1 : 0,
                "totalNumberOfWarnings": 4
            ]
        ]
        if let className {
            entry["className"] = className
        }
        return entry
    }

    private func writeDerivedData(at folder: URL, workspacePath: String?, logs: [[String: Any]]) throws {
        let build: URL = folder.appendingPathComponent("Logs/Build", isDirectory: true)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        var keyed: [String: Any] = [:]
        for log in logs {
            keyed[log["uniqueIdentifier"] as! String] = log
        }
        let manifest: Data = try PropertyListSerialization.data(fromPropertyList: ["logs": keyed], format: .binary, options: 0)
        try manifest.write(to: build.appendingPathComponent("LogStoreManifest.plist"))
        if let workspacePath {
            let info: Data = try PropertyListSerialization.data(fromPropertyList: ["WorkspacePath": workspacePath], format: .xml, options: 0)
            try info.write(to: folder.appendingPathComponent("info.plist"))
        }
    }

    // MARK: - Source classification

    func testSourceFromLogClassName() {
        XCTAssertEqual(BuildSource.from(className: "IDECommandLineBuildLog", title: "Build App"), .cli)
        XCTAssertEqual(BuildSource.from(className: "IDEActivityLogSection", title: "Building project App with scheme App"), .xcode,
                       "the class name wins over the title")
        XCTAssertEqual(BuildSource.from(className: nil, title: "Testing workspace App with scheme AppTests"), .cli)
        XCTAssertEqual(BuildSource.from(className: nil, title: "Build App"), .xcode)
    }

    func testSourceInferredFromTitle() {
        XCTAssertEqual(BuildSource.inferred(fromTitle: "Building project XCBuildStats with scheme XCBuildStats"), .cli)
        XCTAssertEqual(BuildSource.inferred(fromTitle: "Cleaning project App with scheme App and configuration Release"), .cli)
        XCTAssertEqual(BuildSource.inferred(fromTitle: "Testing workspace Sofascore with scheme SofascoreApp"), .cli)
        XCTAssertEqual(BuildSource.inferred(fromTitle: "Build Sofascore"), .xcode)
        XCTAssertEqual(BuildSource.inferred(fromTitle: "Clean Sofascore"), .xcode)
        XCTAssertEqual(BuildSource.inferred(fromTitle: "Build Testing project"), .xcode)
        XCTAssertEqual(BuildSource.inferred(fromTitle: nil), .xcode)
    }

    func testCommandLineCleanTitleCountsAsClean() {
        let start: Date = Date()
        let record: BuildRecord = BuildRecord(
            id: "1", project: "P", scheme: nil, title: "Cleaning project P with scheme P",
            started: start, stopped: start, succeeded: true, errors: 0, warnings: 0, status: "S", source: .cli
        )
        XCTAssertTrue(record.isClean)
    }

    func testManifestScanRecordsSource() throws {
        ManifestScanner.overrideDerivedDataURL = root
        let start: Date = Date(timeIntervalSince1970: 1_800_000_000)
        try writeDerivedData(at: root.appendingPathComponent("App-\(String(repeating: "a", count: 28))"), workspacePath: nil, logs: [
            logEntry(id: "ide", title: "Build App", className: "IDEActivityLogSection", start: start, seconds: 30),
            logEntry(id: "cmd", title: "Building workspace App with scheme App", className: "IDECommandLineBuildLog", start: start, seconds: 40)
        ])

        let byId: [String: BuildRecord] = Dictionary(uniqueKeysWithValues: ManifestScanner.scan().map { ($0.id, $0) })
        XCTAssertEqual(byId["ide"]?.source, .xcode)
        XCTAssertEqual(byId["cmd"]?.source, .cli)
        XCTAssertEqual(byId["cmd"]?.project, "App")
    }

    // MARK: - Invocation parsing

    func testBuildActions() {
        XCTAssertTrue(invocation([]).isBuild, "bare xcodebuild builds")
        XCTAssertTrue(invocation(["-workspace", "A.xcworkspace", "-scheme", "A"]).isBuild)
        XCTAssertTrue(invocation(["-scheme", "A", "build"]).isBuild)
        XCTAssertTrue(invocation(["-quiet", "test"]).isBuild, "an action after a switch is still an action")
        XCTAssertTrue(invocation(["-scheme", "A", "-derivedDataPath", "/tmp/dd", "build-for-testing"]).isBuild)
        XCTAssertTrue(invocation(["archive", "-scheme", "A"]).isBuild)
        XCTAssertTrue(invocation(["clean"]).isBuild)
        XCTAssertEqual(invocation(["clean", "build"]).actions, ["clean", "build"])
        XCTAssertEqual(invocation(["-scheme", "build"]).actions, [], "an option value is not an action")
        XCTAssertEqual(invocation(["-scheme", "test", "build"]).actions, ["build"])
    }

    func testUtilityRunsAreNotBuilds() {
        XCTAssertFalse(invocation(["-showBuildSettings", "-scheme", "A"]).isBuild)
        XCTAssertFalse(invocation(["-workspace", "A.xcworkspace", "-scheme", "A", "-showBuildSettings", "-json"]).isBuild)
        XCTAssertFalse(invocation(["-version"]).isBuild)
        XCTAssertFalse(invocation(["-list", "-json"]).isBuild)
        XCTAssertFalse(invocation(["-resolvePackageDependencies"]).isBuild)
        XCTAssertFalse(invocation(["-exportArchive", "-archivePath", "a.xcarchive"]).isBuild)
        XCTAssertFalse(invocation(["test-without-building", "-scheme", "A"]).isBuild)
    }

    func testContainerFromArgumentsResolvesAgainstWorkingDirectory() {
        let run: XcodebuildInvocation = invocation(["-workspace", "Sofascore.xcworkspace", "-scheme", "SofascoreApp"], in: "/repo/.claude/worktrees/feature")
        let container: XcodebuildInvocation.Container? = run.container { _ in
            XCTFail("named containers must not list the directory")
            return nil
        }
        XCTAssertEqual(container?.path, "/repo/.claude/worktrees/feature/Sofascore.xcworkspace")
        XCTAssertEqual(container?.kind, .workspace)
        XCTAssertEqual(run.projectName(container: container), "Sofascore")
        XCTAssertEqual(run.title(container: container, project: "Sofascore"), "Building workspace Sofascore with scheme SofascoreApp")

        let project: XcodebuildInvocation = invocation(["-project", "/abs/App.xcodeproj", "clean"])
        let projectContainer: XcodebuildInvocation.Container? = project.container { _ in nil }
        XCTAssertEqual(projectContainer?.path, "/abs/App.xcodeproj")
        XCTAssertEqual(project.title(container: projectContainer, project: "App"), "Cleaning project App")
    }

    func testContainerFromWorkingDirectoryListing() {
        let run: XcodebuildInvocation = invocation(["test"], in: "/work/app")
        let workspace: XcodebuildInvocation.Container? = run.container { _ in ["App.xcodeproj", "App.xcworkspace", "README.md"] }
        XCTAssertEqual(workspace?.path, "/work/app/App.xcworkspace", "a workspace is preferred over its project")
        XCTAssertEqual(run.title(container: workspace, project: "App"), "Testing workspace App")

        let project: XcodebuildInvocation.Container? = run.container { _ in ["App.xcodeproj"] }
        XCTAssertEqual(project?.kind, .project)

        let package: XcodebuildInvocation.Container? = run.container { _ in ["Package.swift", "Sources"] }
        XCTAssertEqual(package?.path, "/work/app")
        XCTAssertEqual(package?.kind, .package)
        XCTAssertEqual(run.projectName(container: package), "app")
    }

    func testProjectNameFallbacks() {
        XCTAssertEqual(invocation(["-scheme", "MyScheme"]).projectName(container: nil), "MyScheme")
        XCTAssertEqual(invocation([], in: "/work/folder").projectName(container: nil), "folder")
        XCTAssertEqual(invocation([], in: nil).projectName(container: nil), "Unknown")
    }

    func testDerivedDataPathAndNormalization() {
        XCTAssertEqual(invocation(["-derivedDataPath", "build/dd"], in: "/work/app").derivedDataPath, "/work/app/build/dd")
        XCTAssertEqual(invocation(["-derivedDataPath", "/private/tmp/x/DerivedData/"]).derivedDataPath, "/tmp/x/DerivedData")
        XCTAssertEqual(XcodebuildInvocation.normalized("/private/var/folders/ab/T/tmp.1"), "/var/folders/ab/T/tmp.1")
        XCTAssertEqual(XcodebuildInvocation.normalized("/Users/me/../me/app"), "/Users/me/app")
    }

    func testProcessExitDecoding() {
        XCTAssertEqual(ProcessExit(waitStatus: 0), .exited(0))
        XCTAssertEqual(ProcessExit(waitStatus: 65 << 8), .exited(65))
        XCTAssertEqual(ProcessExit(waitStatus: 9), .signaled(9))
        XCTAssertEqual(ProcessExit(waitStatus: 15 | 0x80), .signaled(15), "core-dump bit does not hide the signal")
    }

    func testParseProcessArguments() {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: Int32(3)) { bytes.append(contentsOf: $0) }
        bytes.append(contentsOf: Array("/usr/bin/xcodebuild".utf8) + [0, 0, 0, 0])
        for argument in ["xcodebuild", "-scheme", "My App"] {
            bytes.append(contentsOf: Array(argument.utf8) + [0])
        }
        bytes.append(contentsOf: Array("CLAUDECODE=1".utf8) + [0])

        let parsed: (executable: String, argv: [String])? = XcodebuildMonitor.parseProcessArguments(bytes)
        XCTAssertEqual(parsed?.executable, "/usr/bin/xcodebuild")
        XCTAssertEqual(parsed?.argv, ["xcodebuild", "-scheme", "My App"])
        XCTAssertNil(XcodebuildMonitor.parseProcessArguments(Array(bytes.prefix(30))), "truncated argv is rejected")
        XCTAssertNil(XcodebuildMonitor.parseProcessArguments([1, 0]))
    }

    func testOnlyXcodeToolchainBinariesCount() {
        XCTAssertTrue(XcodebuildMonitor.isXcodeToolchain("/usr/bin/xcodebuild"))
        XCTAssertTrue(XcodebuildMonitor.isXcodeToolchain("/Applications/Xcode26_6.app/Contents/Developer/usr/bin/xcodebuild"))
        XCTAssertTrue(XcodebuildMonitor.isXcodeToolchain("/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild"))
        XCTAssertFalse(XcodebuildMonitor.isXcodeToolchain("/var/folders/ab/T/xcbs-monitor/bin/xcodebuild"),
                       "the test suite's stand-in must not land in a running app's database")
        XCTAssertFalse(XcodebuildMonitor.isXcodeToolchain("/Library/Developer/CommandLineTools/usr/bin/xcodebuild"),
                       "the Command Line Tools stub cannot build")
    }

    // MARK: - Turning a finished run into records

    private func run(
        _ arguments: [String],
        in directory: String,
        started: Date,
        seconds: TimeInterval,
        exit: ProcessExit = .exited(0)
    ) -> XcodebuildRun {
        return XcodebuildRun(
            pid: 4242,
            invocation: XcodebuildInvocation(arguments: arguments, workingDirectory: directory),
            started: started,
            stopped: started.addingTimeInterval(seconds),
            exit: exit
        )
    }

    func testRunWithoutLogBecomesProcessRecord() {
        let started: Date = Date(timeIntervalSince1970: 1_800_000_000)
        let defaultRoot: URL = root.appendingPathComponent("DerivedData", isDirectory: true)
        let records: [BuildRecord] = run(
            ["-workspace", "App.xcworkspace", "-scheme", "App", "-derivedDataPath", root.appendingPathComponent("tmp-dd").path, "build"],
            in: "/work/app", started: started, seconds: 95, exit: .exited(65)
        ).buildRecords(derivedDataRoot: defaultRoot, home: "/Users/nobody") { _ in nil }

        XCTAssertEqual(records.count, 1)
        let record: BuildRecord? = records.first
        XCTAssertEqual(record?.source, .cli)
        XCTAssertEqual(record?.project, "App")
        XCTAssertEqual(record?.scheme, "App")
        XCTAssertEqual(record?.duration, 95)
        XCTAssertEqual(record?.succeeded, false)
        XCTAssertEqual(record?.status, "E")
        XCTAssertEqual(record?.isClean, false)
        XCTAssertEqual(record?.id, "xcodebuild|4242|1800000000000")
    }

    func testKilledRunIsFailedAndCancelled() {
        let records: [BuildRecord] = run(["build"], in: "/work/app", started: Date(), seconds: 600, exit: .signaled(15))
            .buildRecords(derivedDataRoot: root, home: "/Users/nobody") { _ in ["App.xcodeproj"] }
        XCTAssertEqual(records.first?.succeeded, false)
        XCTAssertEqual(records.first?.status, "C")
        XCTAssertEqual(records.first?.project, "App")
    }

    func testRunPrefersLogEntriesInItsExplicitDerivedData() throws {
        let started: Date = Date(timeIntervalSince1970: 1_800_000_000)
        let derivedData: URL = root.appendingPathComponent("agent-dd", isDirectory: true)
        try writeDerivedData(at: derivedData, workspacePath: "/work/app/App.xcworkspace", logs: [
            logEntry(id: "clean", title: "Cleaning workspace App with scheme App", className: "IDECommandLineBuildLog",
                     start: started.addingTimeInterval(1), seconds: 2),
            logEntry(id: "build", title: "Building workspace App with scheme App", className: "IDECommandLineBuildLog",
                     start: started.addingTimeInterval(4), seconds: 50, status: "E"),
            logEntry(id: "earlier", title: "Building workspace App with scheme App", className: "IDECommandLineBuildLog",
                     start: started.addingTimeInterval(-500), seconds: 50)
        ])

        let records: [BuildRecord] = run(
            ["-workspace", "App.xcworkspace", "-scheme", "App", "-derivedDataPath", derivedData.path, "-resultBundlePath", "r.xcresult", "clean", "build"],
            in: "/work/app", started: started, seconds: 60
        ).buildRecords(derivedDataRoot: root.appendingPathComponent("none"), home: "/Users/nobody") { _ in nil }

        XCTAssertEqual(Set(records.map(\.id)), ["clean", "build"], "only this run's entries, not an earlier run's")
        XCTAssertTrue(records.allSatisfy { $0.source == .cli && $0.project == "App" })
        XCTAssertEqual(records.first { $0.id == "clean" }?.isClean, true)
        XCTAssertEqual(records.first { $0.id == "build" }?.warnings, 4)
    }

    func testRunMatchesDefaultDerivedDataByWorkspacePath() throws {
        let started: Date = Date(timeIntervalSince1970: 1_800_000_000)
        let defaultRoot: URL = root.appendingPathComponent("DerivedData", isDirectory: true)
        // Two worktrees of the same project testing at the same time: each run
        // must only claim the log entries of its own DerivedData folder.
        try writeDerivedData(
            at: defaultRoot.appendingPathComponent("App-\(String(repeating: "a", count: 28))"),
            workspacePath: "/repo/worktrees/one/App.xcworkspace",
            logs: [logEntry(id: "one", title: "Testing workspace App with scheme App", className: "IDECommandLineBuildLog",
                            start: started.addingTimeInterval(3), seconds: 100)]
        )
        try writeDerivedData(
            at: defaultRoot.appendingPathComponent("App-\(String(repeating: "b", count: 28))"),
            workspacePath: "/repo/worktrees/two/App.xcworkspace",
            logs: [
                logEntry(id: "two-ide", title: "Build App", className: "IDEActivityLogSection",
                         start: started.addingTimeInterval(5), seconds: 30)
            ]
        )

        let one: [BuildRecord] = run(["-workspace", "App.xcworkspace", "-scheme", "App", "test"], in: "/repo/worktrees/one", started: started, seconds: 110)
            .buildRecords(derivedDataRoot: defaultRoot, home: "/Users/nobody") { _ in nil }
        XCTAssertEqual(one.map(\.id), ["one"])

        let two: [BuildRecord] = run(["-workspace", "App.xcworkspace", "-scheme", "App", "build"], in: "/repo/worktrees/two", started: started, seconds: 110)
            .buildRecords(derivedDataRoot: defaultRoot, home: "/Users/nobody") { _ in nil }
        XCTAssertEqual(two.count, 1, "an Xcode build in the same folder is not this run's log")
        XCTAssertTrue(two.first?.id.hasPrefix("xcodebuild|") ?? false)

        // No -workspace and an unlistable directory: matched by the working directory.
        let unnamed: [BuildRecord] = run(["test"], in: "/repo/worktrees/one", started: started, seconds: 110)
            .buildRecords(derivedDataRoot: defaultRoot, home: "/Users/nobody") { _ in nil }
        XCTAssertEqual(unnamed.map(\.id), ["one"])

        let elsewhere: [BuildRecord] = run(["test"], in: "/repo/worktrees/three", started: started, seconds: 110)
            .buildRecords(derivedDataRoot: defaultRoot, home: "/Users/nobody") { _ in nil }
        XCTAssertEqual(elsewhere.count, 1)
        XCTAssertTrue(elsewhere.first?.id.hasPrefix("xcodebuild|") ?? false, "another worktree's log is not this run's")
    }

    func testConsentGatedLocationsAreNeverRead() throws {
        let home: String = root.path
        let derivedData: URL = root.appendingPathComponent("Documents/repo/dd", isDirectory: true)
        let started: Date = Date(timeIntervalSince1970: 1_800_000_000)
        try writeDerivedData(at: derivedData, workspacePath: nil, logs: [
            logEntry(id: "gated", title: "Building project App", className: "IDECommandLineBuildLog", start: started.addingTimeInterval(1), seconds: 5)
        ])

        let records: [BuildRecord] = run(["-derivedDataPath", derivedData.path, "-scheme", "AppScheme"], in: root.appendingPathComponent("Documents/repo").path, started: started, seconds: 10)
            .buildRecords(derivedDataRoot: root.appendingPathComponent("none"), home: home) { _ in
                XCTFail("a consent-gated working directory must not be listed")
                return nil
            }
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.project, "AppScheme")
        XCTAssertNotEqual(records.first?.id, "gated")
    }

    // MARK: - Storage

    func testStoreRoundTripsSource() {
        let store: BuildStore = BuildStore(path: root.appendingPathComponent("db.sqlite").path)
        let start: Date = Date(timeIntervalSince1970: 1_800_000_000)
        store.ingest([
            BuildRecord(id: "x", project: "P", scheme: nil, title: "Build P", started: start, stopped: start.addingTimeInterval(10),
                        succeeded: true, errors: 0, warnings: 0, status: "S"),
            BuildRecord(id: "c", project: "P", scheme: nil, title: "Building project P", started: start, stopped: start.addingTimeInterval(20),
                        succeeded: false, errors: 0, warnings: 0, status: "E", source: .cli)
        ])
        let byId: [String: BuildRecord] = Dictionary(uniqueKeysWithValues: store.allBuilds().map { ($0.id, $0) })
        XCTAssertEqual(byId["x"]?.source, .xcode)
        XCTAssertEqual(byId["c"]?.source, .cli)
    }

    func testReconcileFixesSourceOfRowStoredWithout() {
        let store: BuildStore = BuildStore(path: root.appendingPathComponent("db.sqlite").path)
        let start: Date = Date(timeIntervalSince1970: 1_800_000_000)
        func record(_ source: BuildSource) -> BuildRecord {
            return BuildRecord(id: "m", project: "P", scheme: nil, title: "Build P", started: start, stopped: start.addingTimeInterval(5),
                               succeeded: true, errors: 0, warnings: 0, status: "S", source: source)
        }
        // An older app version sharing the database inserted the row first.
        store.ingest([record(.xcode)])
        XCTAssertEqual(store.ingest([record(.cli)]).count, 0)
        XCTAssertEqual(store.reconcileOutcomes([record(.cli)]), 1)
        XCTAssertEqual(store.allBuilds().first?.source, .cli)
        XCTAssertEqual(store.reconcileOutcomes([record(.cli)]), 0, "nothing left to change")
    }

    func testStoreMigratesDatabaseWithoutSourceColumn() throws {
        let path: String = root.appendingPathComponent("old.sqlite").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        let legacy: String = """
        CREATE TABLE builds (id TEXT PRIMARY KEY, project TEXT NOT NULL, scheme TEXT, title TEXT, started REAL NOT NULL,
            stopped REAL NOT NULL, duration REAL NOT NULL, succeeded INTEGER NOT NULL, errors INTEGER NOT NULL,
            warnings INTEGER NOT NULL, status TEXT);
        INSERT INTO builds VALUES ('gui', 'P', 'S', 'Build P', 100, 160, 60, 1, 0, 0, 'S');
        INSERT INTO builds VALUES ('cli', 'P', 'S', 'Testing workspace P with scheme S', 200, 500, 300, 1, 0, 0, 'S');
        """
        XCTAssertEqual(sqlite3_exec(db, legacy, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        let store: BuildStore = BuildStore(path: path)
        let byId: [String: BuildRecord] = Dictionary(uniqueKeysWithValues: store.allBuilds().map { ($0.id, $0) })
        XCTAssertEqual(byId.count, 2, "existing history survives the migration")
        XCTAssertEqual(byId["gui"]?.source, .xcode)
        XCTAssertEqual(byId["cli"]?.source, .cli)

        // An older app version sharing the file keeps inserting without a source.
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        sqlite3_exec(db, "INSERT INTO builds (id, project, scheme, title, started, stopped, duration, succeeded, errors, warnings, status) VALUES ('late', 'P', 'S', 'Building project P', 600, 610, 10, 1, 0, 0, 'S');", nil, nil, nil)
        sqlite3_close(db)
        let reopened: BuildStore = BuildStore(path: path)
        XCTAssertEqual(reopened.allBuilds().first { $0.id == "late" }?.source, .cli, "reclassified on the next open")
    }

    // MARK: - Aggregation

    func testSourceFilterAndStats() {
        let start: Date = Date(timeIntervalSince1970: 1_800_000_000)
        func build(_ id: String, _ source: BuildSource, _ seconds: TimeInterval, offset: TimeInterval = 0) -> BuildRecord {
            return BuildRecord(id: id, project: "P", scheme: nil, title: "Build P", started: start.addingTimeInterval(offset),
                               stopped: start.addingTimeInterval(offset + seconds), succeeded: true, errors: 0, warnings: 0, status: "S", source: source)
        }
        let builds: [BuildRecord] = [build("a", .xcode, 60), build("b", .cli, 120), build("c", .cli, 30, offset: 7200)]
        XCTAssertEqual(builds.filter { SourceFilter.all.includes($0.source) }.count, 3)
        XCTAssertEqual(builds.filter { SourceFilter.xcode.includes($0.source) }.map(\.id), ["a"])
        XCTAssertEqual(builds.filter { SourceFilter.cli.includes($0.source) }.map(\.id), ["b", "c"])

        var calendar: Calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day: DateInterval = Aggregator.periodInterval(grouping: .day, anchor: start, calendar: calendar)

        let stats: [SourceStat] = Aggregator.sourceStats(builds, in: day)
        XCTAssertEqual(stats.map(\.source), [.xcode, .cli])
        XCTAssertEqual(stats.map(\.totalDuration), [60, 150])
        XCTAssertEqual(stats.map(\.count), [1, 2])
        XCTAssertEqual(Aggregator.sourceStats(builds.filter { $0.source == .cli }, in: day).map(\.source), [.cli], "empty sources are omitted")

        let parts: [SourceBar] = Aggregator.sourceBars(builds, in: day, subComponent: .hour, calendar: calendar)
        let total: Double = Aggregator.bars(builds, in: day, subComponent: .hour, calendar: calendar).reduce(0) { $0 + $1.minutes }
        XCTAssertEqual(parts.reduce(0) { $0 + $1.minutes }, total, accuracy: 0.0001, "stacked parts add up to the combined bars")
        XCTAssertEqual(parts.count, 3)
    }

    func testCSVIncludesSource() {
        let start: Date = Date(timeIntervalSince1970: 1_000_000)
        let csv: String = Exporter.makeCSV([
            BuildRecord(id: "1", project: "P", scheme: nil, title: "Building project P", started: start, stopped: start,
                        succeeded: true, errors: 0, warnings: 0, status: "S", source: .cli)
        ])
        let lines: [String] = csv.components(separatedBy: "\n")
        XCTAssertTrue(lines[0].hasSuffix(",source"))
        XCTAssertTrue(lines[1].hasSuffix(",cli"))
    }
}

/// Runs the real monitor against a stand-in `xcodebuild` binary.
final class XcodebuildMonitorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xcbs-monitor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Fake.xcodeproj"), withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    /// A copied system binary is killed by code signing, so compile one: it
    /// sleeps argv[1] seconds and exits with argv[2].
    private func makeFakeXcodebuild() throws -> URL {
        let source: URL = root.appendingPathComponent("fake.c")
        try Data("""
        #include <stdlib.h>
        #include <unistd.h>
        int main(int argc, char **argv) { usleep((useconds_t)(atof(argv[1]) * 1e6)); return atoi(argv[2]); }
        """.utf8).write(to: source)
        let binary: URL = root.appendingPathComponent("bin/xcodebuild")
        let clang: Process = Process()
        clang.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        clang.arguments = ["clang", "-o", binary.path, source.path]
        try clang.run()
        clang.waitUntilExit()
        guard clang.terminationStatus == 0 else {
            throw XCTSkip("clang unavailable")
        }
        return binary
    }

    func testMonitorReportsRunWithTimingAndExitStatus() throws {
        let binary: URL = try makeFakeXcodebuild()
        let lock: NSLock = NSLock()
        var runs: [XcodebuildRun] = []
        let finished: XCTestExpectation = expectation(description: "run finished")
        let process: Process = Process()

        let monitor: XcodebuildMonitor = XcodebuildMonitor(accepts: { $0 == binary.path }) { run in
            lock.lock()
            defer { lock.unlock() }
            // Real xcodebuild runs on this Mac are reported too; keep only ours.
            guard run.pid == process.processIdentifier else {
                return
            }
            runs.append(run)
            finished.fulfill()
        }
        monitor.start()
        defer { monitor.stop() }

        process.executableURL = binary
        process.arguments = ["2.5", "65", "-scheme", "FakeScheme", "build"]
        process.currentDirectoryURL = root
        let launched: Date = Date()
        try process.run()

        wait(for: [finished], timeout: 10)
        lock.lock()
        defer { lock.unlock() }
        let run: XcodebuildRun = try XCTUnwrap(runs.first)
        XCTAssertEqual(run.exit, .exited(65))
        XCTAssertEqual(run.invocation.arguments, ["2.5", "65", "-scheme", "FakeScheme", "build"])
        XCTAssertEqual(run.invocation.workingDirectory.map(XcodebuildInvocation.normalized), XcodebuildInvocation.normalized(root.path))
        XCTAssertEqual(run.started.timeIntervalSince(launched), 0, accuracy: 0.5, "start time comes from the kernel, not the poll")
        XCTAssertEqual(run.stopped.timeIntervalSince(run.started), 2.5, accuracy: 0.6)

        let record: BuildRecord = try XCTUnwrap(run.buildRecords(derivedDataRoot: root.appendingPathComponent("none")).first)
        XCTAssertEqual(record.project, "Fake")
        XCTAssertEqual(record.source, .cli)
        XCTAssertFalse(record.succeeded)
    }

    func testMonitorIgnoresUtilityRuns() throws {
        let binary: URL = try makeFakeXcodebuild()
        let process: Process = Process()
        let reported: XCTestExpectation = expectation(description: "utility run reported")
        reported.isInverted = true
        let monitor: XcodebuildMonitor = XcodebuildMonitor(accepts: { $0 == binary.path }) { run in
            if run.pid == process.processIdentifier {
                reported.fulfill()
            }
        }
        monitor.start()
        defer { monitor.stop() }

        process.executableURL = binary
        process.arguments = ["2", "0", "-showBuildSettings"]
        try process.run()
        process.waitUntilExit()
        wait(for: [reported], timeout: 1.5)
    }
}
