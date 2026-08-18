import XCTest
@testable import XCBuildStats

final class AggregatorTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar: Calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func build(_ project: String, _ start: Date, seconds: TimeInterval, clean: Bool = false, succeeded: Bool = true) -> BuildRecord {
        return BuildRecord(
            id: UUID().uuidString,
            project: project,
            scheme: nil,
            title: clean ? "Clean \(project)" : "Build \(project)",
            started: start,
            stopped: start.addingTimeInterval(seconds),
            succeeded: succeeded,
            errors: succeeded ? 0 : 2,
            warnings: 0,
            status: succeeded ? "S" : "E"
        )
    }

    func testPeriodIntervals() {
        let anchor: Date = date(2026, 7, 6, 12)

        let day: DateInterval = Aggregator.periodInterval(grouping: .day, anchor: anchor, calendar: calendar)
        XCTAssertEqual(day.start, date(2026, 7, 6))
        XCTAssertEqual(day.duration, 86400)

        let month: DateInterval = Aggregator.periodInterval(grouping: .month, anchor: anchor, calendar: calendar)
        XCTAssertEqual(month.start, date(2026, 7, 1))
        XCTAssertEqual(month.end, date(2026, 8, 1))

        let year: DateInterval = Aggregator.periodInterval(grouping: .year, anchor: anchor, calendar: calendar)
        XCTAssertEqual(year.start, date(2026, 1, 1))
        XCTAssertEqual(year.end, date(2027, 1, 1))

        let week: DateInterval = Aggregator.periodInterval(grouping: .week, anchor: anchor, calendar: calendar)
        XCTAssertEqual(week.duration, 7 * 86400)
    }

    func testBuildsBoundaryHalfOpen() {
        let period: DateInterval = Aggregator.periodInterval(grouping: .day, anchor: date(2026, 7, 6), calendar: calendar)
        let atStart: BuildRecord = build("A", period.start, seconds: 10)
        let atEnd: BuildRecord = build("A", period.end, seconds: 10)
        let inside: BuildRecord = build("A", date(2026, 7, 6, 10), seconds: 10)

        let result: [BuildRecord] = Aggregator.builds([atStart, atEnd, inside], in: period)
        XCTAssertEqual(result.count, 2, "period.start included, period.end excluded")
    }

    func testSummaryAndBars() {
        let period: DateInterval = Aggregator.periodInterval(grouping: .day, anchor: date(2026, 7, 6), calendar: calendar)
        let builds: [BuildRecord] = [
            build("A", date(2026, 7, 6, 9), seconds: 120),
            build("A", date(2026, 7, 6, 9, 30), seconds: 60),
            build("A", date(2026, 7, 6, 11), seconds: 30)
        ]

        let summary: PeriodSummary = Aggregator.summary(builds, in: period)
        XCTAssertEqual(summary.count, 3)
        XCTAssertEqual(summary.totalDuration, 210)

        let bars: [Bar] = Aggregator.bars(builds, in: period, subComponent: .hour, calendar: calendar)
        XCTAssertEqual(bars.count, 2, "two distinct hour buckets")
        let hour9: Bar? = bars.first { calendar.component(.hour, from: $0.start) == 9 }
        XCTAssertEqual(hour9?.minutes, 3, "(120 + 60) / 60")
    }

    func testProjectStatsSortedByDuration() {
        let period: DateInterval = Aggregator.periodInterval(grouping: .year, anchor: date(2026, 7, 6), calendar: calendar)
        let builds: [BuildRecord] = [
            build("Small", date(2026, 2, 1), seconds: 10),
            build("Big", date(2026, 3, 1), seconds: 100),
            build("Big", date(2026, 4, 1), seconds: 50)
        ]

        let stats: [ProjectStat] = Aggregator.projectStats(builds, in: period)
        XCTAssertEqual(stats.first?.project, "Big")
        XCTAssertEqual(stats.first?.totalDuration, 150)
        XCTAssertEqual(stats.first?.count, 2)
    }

    func testSummaryTracksFailures() {
        let period: DateInterval = Aggregator.periodInterval(grouping: .day, anchor: date(2026, 7, 6), calendar: calendar)
        let builds: [BuildRecord] = [
            build("A", date(2026, 7, 6, 9), seconds: 60, succeeded: true),
            build("A", date(2026, 7, 6, 10), seconds: 30, succeeded: false),
            build("A", date(2026, 7, 6, 11), seconds: 30, succeeded: false)
        ]

        let summary: PeriodSummary = Aggregator.summary(builds, in: period)
        XCTAssertEqual(summary.count, 3)
        XCTAssertEqual(summary.failedCount, 2)
        XCTAssertEqual(summary.successCount, 1)
        XCTAssertEqual(summary.failedDuration, 60)
        XCTAssertEqual(summary.successRate, 1.0 / 3.0, accuracy: 0.0001)
    }

    func testCanGoForward() {
        let now: Date = date(2026, 7, 6, 12)
        let past: DateInterval = Aggregator.periodInterval(grouping: .day, anchor: date(2026, 7, 4), calendar: calendar)
        XCTAssertTrue(Aggregator.canGoForward(from: past, now: now))

        let current: DateInterval = Aggregator.periodInterval(grouping: .day, anchor: now, calendar: calendar)
        XCTAssertFalse(Aggregator.canGoForward(from: current, now: now))
    }

    func testCurrentPeriodTracksRealDay() {
        let lateJul6: Date = date(2026, 7, 6, 23, 30)
        let earlyJul7: Date = date(2026, 7, 7, 0, 30)
        XCTAssertEqual(Aggregator.periodInterval(grouping: .day, now: lateJul6, offset: 0, calendar: calendar).start, date(2026, 7, 6))
        XCTAssertEqual(Aggregator.periodInterval(grouping: .day, now: earlyJul7, offset: 0, calendar: calendar).start, date(2026, 7, 7))
    }

    func testNegativeOffsetIsPreviousPeriod() {
        let now: Date = date(2026, 7, 15, 12)
        XCTAssertEqual(Aggregator.periodInterval(grouping: .day, now: now, offset: -1, calendar: calendar).start, date(2026, 7, 14))
        XCTAssertEqual(Aggregator.periodInterval(grouping: .month, now: now, offset: -1, calendar: calendar).start, date(2026, 6, 1))
        XCTAssertEqual(Aggregator.periodInterval(grouping: .year, now: now, offset: -1, calendar: calendar).start, date(2025, 1, 1))
    }

    func testDayRolloverSummary() {
        let builds: [BuildRecord] = [build("A", date(2026, 7, 6, 10), seconds: 48 * 60)]
        let now: Date = date(2026, 7, 7, 9)
        let today: DateInterval = Aggregator.periodInterval(grouping: .day, now: now, offset: 0, calendar: calendar)
        let yesterday: DateInterval = Aggregator.periodInterval(grouping: .day, now: now, offset: -1, calendar: calendar)
        XCTAssertEqual(Aggregator.summary(builds, in: today).totalDuration, 0, "today must be empty after rollover")
        XCTAssertEqual(Aggregator.summary(builds, in: yesterday).totalDuration, 48 * 60)
    }

    func testCanGoForwardOffset() {
        let now: Date = date(2026, 7, 7, 12)
        let current: DateInterval = Aggregator.periodInterval(grouping: .day, now: now, offset: 0, calendar: calendar)
        let past: DateInterval = Aggregator.periodInterval(grouping: .day, now: now, offset: -1, calendar: calendar)
        XCTAssertFalse(Aggregator.canGoForward(from: current, now: now))
        XCTAssertTrue(Aggregator.canGoForward(from: past, now: now))
    }

    func testSuccessPercentNeverContradictsCounts() {
        func summary(count: Int, failed: Int) -> PeriodSummary {
            return PeriodSummary(totalDuration: 0, count: count, failedCount: failed, failedDuration: 0)
        }
        XCTAssertEqual(summary(count: 200, failed: 1).successPercent, 99, "must not show 100% next to a failure")
        XCTAssertEqual(summary(count: 200, failed: 199).successPercent, 1, "must not show 0% next to a success")
        XCTAssertEqual(summary(count: 15, failed: 5).successPercent, 67)
        XCTAssertEqual(summary(count: 10, failed: 0).successPercent, 100)
        XCTAssertEqual(summary(count: 10, failed: 10).successPercent, 0)
        XCTAssertEqual(summary(count: 0, failed: 0).successPercent, 0)
    }

    func testTimelineGroupsByPeriod() {
        let builds: [BuildRecord] = [
            build("A", date(2026, 7, 6, 9), seconds: 100),
            build("A", date(2026, 7, 6, 15), seconds: 50),
            build("B", date(2026, 7, 7, 9), seconds: 30)
        ]
        let rows: [TimelineRow] = Aggregator.timeline(builds, grouping: .day, calendar: calendar)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].start, date(2026, 7, 6))
        XCTAssertEqual(rows[0].totalDuration, 150)
        XCTAssertEqual(rows[0].count, 2)
        XCTAssertEqual(rows[1].totalDuration, 30)
    }

    func testDSTTransitionDayStillSumsCorrectly() {
        var zagreb: Calendar = Calendar(identifier: .gregorian)
        zagreb.timeZone = TimeZone(identifier: "Europe/Zagreb")!
        zagreb.firstWeekday = 2
        // 2026-03-29: clocks jump forward in Europe, the day has 23 hours.
        let anchor: Date = zagreb.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 12))!
        let period: DateInterval = Aggregator.periodInterval(grouping: .day, anchor: anchor, calendar: zagreb)
        XCTAssertEqual(period.duration, 23 * 3600, "DST-forward day is 23h")

        let early: Date = zagreb.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 1))!
        let late: Date = zagreb.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 20))!
        let builds: [BuildRecord] = [build("A", early, seconds: 100), build("A", late, seconds: 50)]
        XCTAssertEqual(Aggregator.summary(builds, in: period).totalDuration, 150)
        let bars: [Bar] = Aggregator.bars(builds, in: period, subComponent: .hour, calendar: zagreb)
        XCTAssertEqual(bars.reduce(0) { $0 + $1.minutes }, 150.0 / 60.0, accuracy: 0.0001)
    }

    func testWeekRespectsCalendarFirstWeekday() {
        // Sunday Jul 5 2026. Monday-start week → previous week; Sunday-start → same week as Jul 6? No:
        // with firstWeekday=2 the week containing Sunday ends that day; with firstWeekday=1 it starts that day.
        let sunday: Date = date(2026, 7, 5, 12)
        let mondayStart: DateInterval = Aggregator.periodInterval(grouping: .week, anchor: sunday, calendar: calendar)
        XCTAssertEqual(mondayStart.start, date(2026, 6, 29), "Monday-start calendar: week of Jun 29 – Jul 5")

        var sundayCalendar: Calendar = calendar
        sundayCalendar.firstWeekday = 1
        let sundayStart: DateInterval = Aggregator.periodInterval(grouping: .week, anchor: sunday, calendar: sundayCalendar)
        XCTAssertEqual(sundayStart.start, date(2026, 7, 5), "Sunday-start calendar: week begins on the anchor Sunday")
    }

    func testPreviousPeriodDeltaNilWithoutPreviousData() {
        let now: Date = date(2026, 7, 7, 12)
        let todayOnly: [BuildRecord] = [build("A", date(2026, 7, 7, 9), seconds: 100)]
        XCTAssertNil(Aggregator.previousPeriodDelta(todayOnly, grouping: .day, now: now, offset: 0, calendar: calendar), "no builds yesterday → no delta")
        XCTAssertNil(Aggregator.previousPeriodDelta([], grouping: .week, now: now, offset: 0, calendar: calendar))
    }

    func testPreviousPeriodDeltaFraction() {
        let now: Date = date(2026, 7, 7, 12)
        let builds: [BuildRecord] = [
            build("A", date(2026, 7, 6, 9), seconds: 100),
            build("A", date(2026, 7, 7, 9), seconds: 50)
        ]
        let delta: Double? = Aggregator.previousPeriodDelta(builds, grouping: .day, now: now, offset: 0, calendar: calendar)
        XCTAssertEqual(delta ?? .nan, -0.5, accuracy: 0.0001, "today 50s vs yesterday 100s → -50%")

        let doubled: Double? = Aggregator.previousPeriodDelta(
            builds + [build("A", date(2026, 7, 7, 10), seconds: 150)],
            grouping: .day, now: now, offset: 0, calendar: calendar
        )
        XCTAssertEqual(doubled ?? .nan, 1.0, accuracy: 0.0001, "today 200s vs yesterday 100s → +100%")
    }

    func testPreviousPeriodDeltaEmptyCurrentIsFullDrop() {
        let now: Date = date(2026, 7, 7, 12)
        let yesterdayOnly: [BuildRecord] = [build("A", date(2026, 7, 6, 9), seconds: 100)]
        let delta: Double? = Aggregator.previousPeriodDelta(yesterdayOnly, grouping: .day, now: now, offset: 0, calendar: calendar)
        XCTAssertEqual(delta ?? .nan, -1.0, accuracy: 0.0001)
    }

    func testPreviousPeriodDeltaRespectsOffsetAndGrouping() {
        let now: Date = date(2026, 7, 15, 12)
        let builds: [BuildRecord] = [
            build("A", date(2026, 5, 10), seconds: 100),
            build("A", date(2026, 6, 10), seconds: 300)
        ]
        let juneVsMay: Double? = Aggregator.previousPeriodDelta(builds, grouping: .month, now: now, offset: -1, calendar: calendar)
        XCTAssertEqual(juneVsMay ?? .nan, 2.0, accuracy: 0.0001, "June 300s vs May 100s → +200%")
        XCTAssertNil(Aggregator.previousPeriodDelta(builds, grouping: .month, now: now, offset: -2, calendar: calendar), "May vs April: April empty → nil")
    }
}
