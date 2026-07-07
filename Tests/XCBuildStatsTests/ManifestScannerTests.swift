import XCTest
@testable import XCBuildStats

final class ManifestScannerTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xcbs-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        ManifestScanner.overrideDerivedDataURL = tempRoot
    }

    override func tearDownWithError() throws {
        ManifestScanner.overrideDerivedDataURL = nil
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func hash(_ letter: String = "a") -> String {
        return String(repeating: letter, count: 28)
    }

    private func record(
        id: String,
        title: String,
        start: Double,
        stop: Double,
        domain: String = "Xcode.IDEActivityLogDomainType.BuildLog",
        status: String = "S",
        errors: Int = 0,
        warnings: Int = 0
    ) -> [String: Any] {
        return [
            "domainType": domain,
            "uniqueIdentifier": id,
            "title": title,
            "signature": title,
            "timeStartedRecording": start,
            "timeStoppedRecording": stop,
            "schemeIdentifier-schemeName": "Scheme",
            "primaryObservable": [
                "highLevelStatus": status,
                "totalNumberOfErrors": errors,
                "totalNumberOfWarnings": warnings
            ]
        ]
    }

    private func writeManifest(project: String, records: [[String: Any]]) throws {
        let build: URL = tempRoot
            .appendingPathComponent("\(project)-\(hash())", isDirectory: true)
            .appendingPathComponent("Logs/Build", isDirectory: true)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        var logs: [String: Any] = [:]
        for (index, record) in records.enumerated() {
            logs["log\(index)"] = record
        }
        let manifest: [String: Any] = ["logFormatVersion": 11, "logs": logs]
        let data: Data = try PropertyListSerialization.data(fromPropertyList: manifest, format: .binary, options: 0)
        try data.write(to: build.appendingPathComponent("LogStoreManifest.plist"))
    }

    func testScanClassifiesBuildsAndFiltersInvalid() throws {
        try writeManifest(project: "MyApp", records: [
            record(id: "b1", title: "Build MyApp", start: 100, stop: 160, warnings: 5),
            record(id: "c1", title: "Clean MyApp", start: 200, stop: 209),
            record(id: "p1", title: "Resolve Packages", start: 300, stop: 305, domain: "Xcode.IDEActivityLogDomainType.PackageLog"),
            record(id: "x1", title: "Build MyApp", start: 500, stop: 400, status: "E", errors: 2)
        ])

        let builds: [BuildRecord] = ManifestScanner.scan()
        XCTAssertEqual(builds.count, 2, "package log and stop<start record must be skipped")

        let byId: [String: BuildRecord] = Dictionary(uniqueKeysWithValues: builds.map { ($0.id, $0) })
        XCTAssertEqual(byId["b1"]?.project, "MyApp")
        XCTAssertEqual(byId["b1"]?.duration, 60)
        XCTAssertEqual(byId["b1"]?.isClean, false)
        XCTAssertEqual(byId["b1"]?.warnings, 5)
        XCTAssertEqual(byId["c1"]?.isClean, true)
        XCTAssertEqual(byId["c1"]?.duration, 9)
        XCTAssertNil(byId["p1"])
        XCTAssertNil(byId["x1"])
    }

    func testProjectFolderNamesFiltersByHashPattern() throws {
        try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent("MyApp-\(hash())"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent("Other-\(hash("b"))"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent("ModuleCache.noindex"), withIntermediateDirectories: true)

        XCTAssertEqual(ManifestScanner.projectFolderNames(), Set(["MyApp-\(hash())", "Other-\(hash("b"))"]))
    }

    func testProjectFolderNamesReturnsNilWhenUnreadable() {
        ManifestScanner.overrideDerivedDataURL = tempRoot.appendingPathComponent("does-not-exist", isDirectory: true)
        XCTAssertNil(ManifestScanner.projectFolderNames(), "a failed directory read must not look like an empty DerivedData")
    }

    func testStripHash() {
        XCTAssertEqual(ManifestScanner.stripDerivedDataHash("MyApp-\(hash())"), "MyApp")
        XCTAssertEqual(ManifestScanner.stripDerivedDataHash("No-Hash"), "No-Hash")
    }

    func testDeletionEvents() {
        let date: Date = Date(timeIntervalSince1970: 1_000_000)
        let a: String = "A-\(hash())"
        let b: String = "B-\(hash("b"))"

        XCTAssertEqual(ManifestScanner.deletionEvents(previous: [], current: [a], at: date).count, 0, "first scan must not emit")

        let removedOne: [BuildEvent] = ManifestScanner.deletionEvents(previous: [a, b], current: [a], at: date)
        XCTAssertEqual(removedOne.count, 1)
        XCTAssertEqual(removedOne.first?.project, "B")
        XCTAssertEqual(removedOne.first?.type, BuildEventType.derivedDataDeleted)

        XCTAssertEqual(ManifestScanner.deletionEvents(previous: [a, b], current: [], at: date).count, 2, "whole DerivedData wipe emits one per project")
        XCTAssertEqual(ManifestScanner.deletionEvents(previous: [a], current: [a, b], at: date).count, 0, "new folders are not deletions")
    }
}
