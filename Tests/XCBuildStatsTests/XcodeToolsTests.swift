import XCTest
@testable import XCBuildStats

final class XcodeToolsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xcbs-tools-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    func testDeleteDerivedDataContentsKeepsRoot() throws {
        let project: URL = root.appendingPathComponent("MyApp-abcdefghijklmnopqrstuvwxyzab/Logs")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appendingPathComponent("ModuleCache.noindex"))

        XCTAssertTrue(XcodeTools.deleteDerivedDataContents(at: root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path), "root folder must survive for the FSEvents watcher")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [], "all contents removed")
    }

    func testDeleteDerivedDataContentsFailsWhenEmptyOrMissing() {
        XCTAssertFalse(XcodeTools.deleteDerivedDataContents(at: root), "nothing to delete → report failure for ✗ feedback")
        XCTAssertFalse(XcodeTools.deleteDerivedDataContents(at: root.appendingPathComponent("missing")))
    }

    func testResetPackageCaches() throws {
        let fileManager: FileManager = .default
        let cache: URL = root.appendingPathComponent("org.swift.swiftpm")
        try fileManager.createDirectory(at: cache.appendingPathComponent("repositories"), withIntermediateDirectories: true)
        let derivedData: URL = root.appendingPathComponent("DerivedData")
        let project: URL = derivedData.appendingPathComponent("MyApp-abcdefghijklmnopqrstuvwxyzab")
        let sourcePackages: URL = project.appendingPathComponent("SourcePackages")
        try fileManager.createDirectory(at: sourcePackages.appendingPathComponent("checkouts"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: project.appendingPathComponent("Logs/Build"), withIntermediateDirectories: true)

        XCTAssertTrue(XcodeTools.resetPackageCaches(cache: cache, derivedData: derivedData))
        XCTAssertFalse(fileManager.fileExists(atPath: cache.path), "global SwiftPM cache removed")
        XCTAssertFalse(fileManager.fileExists(atPath: sourcePackages.path), "per-project SourcePackages removed")
        XCTAssertTrue(fileManager.fileExists(atPath: project.appendingPathComponent("Logs/Build").path), "the rest of the project folder must survive")
        XCTAssertFalse(XcodeTools.resetPackageCaches(cache: cache, derivedData: derivedData), "already gone → nothing to reset")
    }

    func testResolveXcodeAppPathPrefersRememberedVersion() {
        let disk: Set<String> = ["/Applications/Xcode-beta.app", "/Applications/Xcode26_0.app"]
        let exists: (String) -> Bool = { disk.contains($0) }

        XCTAssertEqual(
            XcodeTools.resolveXcodeAppPath(remembered: "/Applications/Xcode-beta.app", developerDir: "/Applications/Xcode26_0.app/Contents/Developer", exists: exists),
            "/Applications/Xcode-beta.app",
            "the Xcode we last quit wins over xcode-select"
        )
        XCTAssertEqual(
            XcodeTools.resolveXcodeAppPath(remembered: "/Applications/Deleted.app", developerDir: "/Applications/Xcode26_0.app/Contents/Developer", exists: exists),
            "/Applications/Xcode26_0.app",
            "a remembered Xcode that was deleted falls back to xcode-select"
        )
        XCTAssertNil(
            XcodeTools.resolveXcodeAppPath(remembered: nil, developerDir: "/Library/Developer/CommandLineTools", exists: exists),
            "CommandLineTools selection is not an app → defer to Launch Services"
        )
        XCTAssertNil(XcodeTools.resolveXcodeAppPath(remembered: nil, developerDir: nil, exists: exists))
    }

    func testResetPackageCachesWithoutDerivedData() {
        XCTAssertFalse(XcodeTools.resetPackageCaches(
            cache: root.appendingPathComponent("missing-cache"),
            derivedData: root.appendingPathComponent("missing-dd")
        ), "fresh machine: nothing anywhere → ✗ feedback, no crash")
    }
}
