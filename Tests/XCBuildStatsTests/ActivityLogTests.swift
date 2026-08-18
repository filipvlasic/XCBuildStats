import XCTest
@testable import XCBuildStats

final class ActivityLogTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xcbs-log-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeGzip(_ content: String, to url: URL) throws {
        let plain: URL = url.appendingPathExtension("plain")
        try Data(content.utf8).write(to: plain)
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-c", plain.path]
        let pipe: Pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data: Data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try data.write(to: url)
    }

    private func result(_ slfContent: String) throws -> Bool? {
        let id: String = UUID().uuidString
        let url: URL = root.appendingPathComponent("\(id).xcactivitylog")
        try writeGzip(slfContent, to: url)
        return ManifestScanner.activityLogResult(id: id, at: url)
    }

    func testGunzipRoundtrip() throws {
        let content: String = String(repeating: "SLF0 xcactivitylog noise · ", count: 5000)
        let url: URL = root.appendingPathComponent("roundtrip.gz")
        try writeGzip(content, to: url)
        let unzipped: Data = try XCTUnwrap(ManifestScanner.gunzip(try Data(contentsOf: url)))
        XCTAssertEqual(String(decoding: unzipped, as: UTF8.self), content)
    }

    func testGunzipRejectsGarbage() {
        XCTAssertNil(ManifestScanner.gunzip(Data("definitely not gzip".utf8)))
        XCTAssertNil(ManifestScanner.gunzip(Data()))
    }

    func testStatusMarkers() throws {
        XCTAssertEqual(try result(#"0#---36"DEAD-BEEF15"Build succeeded-0("#), true)
        XCTAssertEqual(try result(#"0#---36"DEAD-BEEF26"Build finished with errors-0("#), true, "lint/script error diagnostics but the build completed")
        XCTAssertEqual(try result(#"0#---36"DEAD-BEEF12"Build failed-0("#), false)
        XCTAssertNil(try result(#"0#---36"DEAD-BEEF13"Build stopped-0("#), "unknown status → fall back to counters")
        XCTAssertEqual(
            try result(#"script echo: Build succeeded (fake) … later 12"Build failed-0("#),
            false,
            "a real failure marker wins over loose text"
        )
    }

    func testMissingLogFile() {
        XCTAssertNil(ManifestScanner.activityLogResult(id: UUID().uuidString, at: root.appendingPathComponent("missing.xcactivitylog")))
    }
}
