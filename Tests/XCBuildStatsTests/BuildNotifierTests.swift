import XCTest
@testable import XCBuildStats

final class BuildNotifierTests: XCTestCase {
    private func build(duration: TimeInterval, stopped: Date, clean: Bool = false) -> BuildRecord {
        return BuildRecord(
            id: UUID().uuidString,
            project: "P",
            scheme: nil,
            title: clean ? "Clean P" : "Build P",
            started: stopped.addingTimeInterval(-duration),
            stopped: stopped,
            succeeded: true,
            errors: 0,
            warnings: 0,
            status: "S"
        )
    }

    func testShouldNotifyThreshold() {
        let now: Date = Date(timeIntervalSince1970: 1_000_000)
        let fresh: Date = now.addingTimeInterval(-10)
        XCTAssertTrue(BuildNotifier.shouldNotify(build(duration: 150, stopped: fresh), threshold: 150, now: now), "exactly at threshold must notify")
        XCTAssertFalse(BuildNotifier.shouldNotify(build(duration: 149, stopped: fresh), threshold: 150, now: now))
        XCTAssertTrue(BuildNotifier.shouldNotify(build(duration: 3, stopped: fresh), threshold: 0, now: now), "zero threshold = all builds")
    }

    func testShouldNotifySkipsCleansAndBackfill() {
        let now: Date = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(BuildNotifier.shouldNotify(build(duration: 300, stopped: now.addingTimeInterval(-10), clean: true), threshold: 0, now: now), "cleans are not builds")
        XCTAssertFalse(
            BuildNotifier.shouldNotify(build(duration: 300, stopped: now.addingTimeInterval(-3600)), threshold: 0, now: now),
            "old builds ingested after launch/wake are backfill, not fresh finishes"
        )
        XCTAssertTrue(BuildNotifier.shouldNotify(build(duration: 300, stopped: now.addingTimeInterval(-BuildNotifier.freshnessWindow)), threshold: 0, now: now))
    }

    func testThresholdLabels() {
        XCTAssertEqual(BuildNotifier.thresholdLabel(0), "All builds")
        XCTAssertEqual(BuildNotifier.thresholdLabel(30), "30 sec")
        XCTAssertEqual(BuildNotifier.thresholdLabel(60), "1 min")
        XCTAssertEqual(BuildNotifier.thresholdLabel(90), "1.5 min")
        XCTAssertEqual(BuildNotifier.thresholdLabel(150), "2.5 min")
        XCTAssertEqual(BuildNotifier.thresholdLabel(600), "10 min")
    }

    func testThresholdSliderBounds() {
        XCTAssertEqual(BuildNotifier.thresholdRange.lowerBound, 30, "all-builds is the checkbox, not a slider position")
        XCTAssertEqual(BuildNotifier.thresholdRange.upperBound, 600)
        XCTAssertEqual(BuildNotifier.thresholdStep, 30, "half-minute gradation")
        XCTAssertEqual(BuildNotifier.defaultThreshold, 120)
    }
}
