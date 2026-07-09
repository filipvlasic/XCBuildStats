import XCTest
@testable import XCBuildStats

final class FormatExportTests: XCTestCase {
    func testDurationFormatting() {
        XCTAssertEqual(Format.duration(0), "0s")
        XCTAssertEqual(Format.duration(45), "45s")
        XCTAssertEqual(Format.duration(60), "1m 0s")
        XCTAssertEqual(Format.duration(3661), "1h 1m")
        XCTAssertEqual(Format.duration(-50), "0s", "negative durations must clamp")
        XCTAssertEqual(Format.compact(-50), "0m")
        XCTAssertEqual(Format.compact(3660), "1h1m")
    }

    func testRelativeFormatting() {
        let now: Date = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(Format.relative(now.addingTimeInterval(-30), to: now), "just now")
        XCTAssertEqual(Format.relative(now.addingTimeInterval(-120), to: now), "2m ago")
        XCTAssertEqual(Format.relative(now.addingTimeInterval(-7200), to: now), "2h ago")
        XCTAssertEqual(Format.relative(now.addingTimeInterval(-172_800), to: now), "2d ago")
        XCTAssertEqual(Format.relative(now.addingTimeInterval(60), to: now), "just now", "future dates must not crash")
    }

    func testSummaryLine() {
        let week: PeriodSummary = PeriodSummary(totalDuration: 4620, count: 62, failedCount: 19, failedDuration: 600)
        XCTAssertEqual(
            DashboardViewModel.summaryLine(periodTitle: "this week", summary: week),
            "This week: 1h 17m · 62 builds · 69% success"
        )
        let single: PeriodSummary = PeriodSummary(totalDuration: 45, count: 1, failedCount: 0, failedDuration: 0)
        XCTAssertEqual(
            DashboardViewModel.summaryLine(periodTitle: "today", summary: single),
            "Today: 45s · 1 build · 100% success"
        )
    }

    func testCSVEscaping() {
        let start: Date = Date(timeIntervalSince1970: 1_000_000)
        let build: BuildRecord = BuildRecord(
            id: "1",
            project: "My, App",
            scheme: "S\"x",
            title: "Build X",
            started: start,
            stopped: start.addingTimeInterval(60),
            succeeded: false,
            errors: 1,
            warnings: 2,
            status: "E"
        )
        let csv: String = Exporter.makeCSV([build])
        let header: String = csv.components(separatedBy: "\n").first ?? ""
        XCTAssertTrue(header.hasPrefix("project,scheme,title,"))
        XCTAssertTrue(csv.contains("\"My, App\""), "comma field must be quoted")
        XCTAssertTrue(csv.contains("\"S\"\"x\""), "quote must be doubled and field quoted")
    }

    func testLoginItemUnsupportedOutsideAppBundle() {
        XCTAssertFalse(LoginItem.isSupported, "running as a test/CLI is not an .app bundle")
    }

    func testBuildRecordCleanClassification() {
        func make(_ title: String?) -> BuildRecord {
            return BuildRecord(id: "1", project: "P", scheme: nil, title: title, started: Date(), stopped: Date(), succeeded: true, errors: 0, warnings: 0, status: "S")
        }
        XCTAssertTrue(make("Clean MyApp").isClean)
        XCTAssertFalse(make("Build MyApp").isClean)
        XCTAssertFalse(make(nil).isClean)
    }
}
