import Foundation

enum Grouping: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"

    var id: String {
        return rawValue
    }

    /// Component shifted when navigating to the previous/next period.
    var navComponent: Calendar.Component {
        switch self {
        case .day:
            return .day
        case .week:
            return .weekOfYear
        case .month:
            return .month
        case .year:
            return .year
        }
    }

    /// Component each bar on the chart represents within the selected period.
    var subComponent: Calendar.Component {
        switch self {
        case .day:
            return .hour
        case .week, .month:
            return .day
        case .year:
            return .month
        }
    }

    /// Component used to define the period interval containing the anchor date.
    var periodComponent: Calendar.Component {
        switch self {
        case .day:
            return .day
        case .week:
            return .weekOfYear
        case .month:
            return .month
        case .year:
            return .year
        }
    }
}

/// Which builds the dashboard counts: everything, or only one source.
enum SourceFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case xcode = "Xcode"
    case cli = "CLI"

    var id: String {
        return rawValue
    }

    func includes(_ source: BuildSource) -> Bool {
        switch self {
        case .all:
            return true
        case .xcode:
            return source == .xcode
        case .cli:
            return source == .cli
        }
    }
}

struct Bar: Identifiable {
    let start: Date
    let minutes: Double

    var id: Date {
        return start
    }
}

struct PeriodSummary {
    let totalDuration: TimeInterval
    let count: Int
    let failedCount: Int
    let failedDuration: TimeInterval

    var averageDuration: TimeInterval {
        guard count > 0 else {
            return 0
        }
        return totalDuration / Double(count)
    }

    var successCount: Int {
        return count - failedCount
    }

    var successRate: Double {
        guard count > 0 else {
            return 0
        }
        return Double(successCount) / Double(count)
    }

    /// Rounded percentage clamped so it never contradicts the counts next to it:
    /// with any failure it cannot display 100%, with any success it cannot display 0%.
    var successPercent: Int {
        guard count > 0 else {
            return 0
        }
        var percent: Int = Int((successRate * 100).rounded())
        if failedCount > 0 {
            percent = min(percent, 99)
        }
        if successCount > 0 {
            percent = max(percent, 1)
        }
        return percent
    }
}

/// One source's share of a chart bar.
struct SourceBar: Identifiable {
    let start: Date
    let source: BuildSource
    let minutes: Double

    var id: String {
        return "\(source.rawValue)|\(start.timeIntervalSince1970)"
    }
}

struct SourceStat: Identifiable {
    let source: BuildSource
    let totalDuration: TimeInterval
    let count: Int

    var id: BuildSource {
        return source
    }
}

struct ProjectStat: Identifiable {
    let project: String
    let totalDuration: TimeInterval
    let count: Int

    var id: String {
        return project
    }
}

struct TimelineRow: Identifiable {
    let start: Date
    let totalDuration: TimeInterval
    let count: Int

    var id: Date {
        return start
    }
}

enum Aggregator {
    static func canGoForward(from period: DateInterval, now: Date) -> Bool {
        return period.end <= now
    }

    static func periodInterval(grouping: Grouping, anchor: Date, calendar: Calendar) -> DateInterval {
        if let interval: DateInterval = calendar.dateInterval(of: grouping.periodComponent, for: anchor) {
            return interval
        }
        let start: Date = calendar.startOfDay(for: anchor)
        return DateInterval(start: start, duration: 86400)
    }

    static func periodInterval(grouping: Grouping, now: Date, offset: Int, calendar: Calendar) -> DateInterval {
        let anchor: Date = calendar.date(byAdding: grouping.navComponent, value: offset, to: now) ?? now
        return periodInterval(grouping: grouping, anchor: anchor, calendar: calendar)
    }

    static func builds(_ builds: [BuildRecord], in period: DateInterval) -> [BuildRecord] {
        return builds.filter { $0.started >= period.start && $0.started < period.end }
    }

    static func summary(_ builds: [BuildRecord], in period: DateInterval) -> PeriodSummary {
        let inPeriod: [BuildRecord] = self.builds(builds, in: period)
        let total: TimeInterval = inPeriod.reduce(0) { $0 + $1.duration }
        let failed: [BuildRecord] = inPeriod.filter { !$0.succeeded }
        let failedDuration: TimeInterval = failed.reduce(0) { $0 + $1.duration }
        return PeriodSummary(
            totalDuration: total,
            count: inPeriod.count,
            failedCount: failed.count,
            failedDuration: failedDuration
        )
    }

    static func bars(_ builds: [BuildRecord], in period: DateInterval, subComponent: Calendar.Component, calendar: Calendar) -> [Bar] {
        var totals: [Date: TimeInterval] = [:]
        for build in self.builds(builds, in: period) {
            let key: Date = calendar.dateInterval(of: subComponent, for: build.started)?.start ?? build.started
            totals[key, default: 0] += build.duration
        }
        return totals
            .map { Bar(start: $0.key, minutes: $0.value / 60) }
            .sorted { $0.start < $1.start }
    }

    static func sourceBars(_ builds: [BuildRecord], in period: DateInterval, subComponent: Calendar.Component, calendar: Calendar) -> [SourceBar] {
        return BuildSource.allCases.flatMap { source in
            bars(builds.filter { $0.source == source }, in: period, subComponent: subComponent, calendar: calendar)
                .map { SourceBar(start: $0.start, source: source, minutes: $0.minutes) }
        }
    }

    /// Per-source totals, in `BuildSource` order, omitting sources with no builds.
    static func sourceStats(_ builds: [BuildRecord], in period: DateInterval) -> [SourceStat] {
        let inPeriod: [BuildRecord] = self.builds(builds, in: period)
        return BuildSource.allCases.compactMap { source in
            let matching: [BuildRecord] = inPeriod.filter { $0.source == source }
            guard !matching.isEmpty else {
                return nil
            }
            return SourceStat(source: source, totalDuration: matching.reduce(0) { $0 + $1.duration }, count: matching.count)
        }
    }

    /// Fractional change in total build time for the period at `offset` versus the
    /// immediately preceding period of the same granularity. `nil` when the previous
    /// period has no builds to compare against.
    static func previousPeriodDelta(_ builds: [BuildRecord], grouping: Grouping, now: Date, offset: Int, calendar: Calendar) -> Double? {
        let current: PeriodSummary = summary(builds, in: periodInterval(grouping: grouping, now: now, offset: offset, calendar: calendar))
        let previous: PeriodSummary = summary(builds, in: periodInterval(grouping: grouping, now: now, offset: offset - 1, calendar: calendar))
        guard previous.count > 0, previous.totalDuration > 0 else {
            return nil
        }
        return (current.totalDuration - previous.totalDuration) / previous.totalDuration
    }

    static func projectStats(_ builds: [BuildRecord], in period: DateInterval) -> [ProjectStat] {
        var durations: [String: TimeInterval] = [:]
        var counts: [String: Int] = [:]
        for build in self.builds(builds, in: period) {
            durations[build.project, default: 0] += build.duration
            counts[build.project, default: 0] += 1
        }
        return durations
            .map { ProjectStat(project: $0.key, totalDuration: $0.value, count: counts[$0.key] ?? 0) }
            .sorted { $0.totalDuration > $1.totalDuration }
    }

    static func timeline(_ builds: [BuildRecord], grouping: Grouping, calendar: Calendar = .current) -> [TimelineRow] {
        var durations: [Date: TimeInterval] = [:]
        var counts: [Date: Int] = [:]
        for build in builds {
            let key: Date = calendar.dateInterval(of: grouping.periodComponent, for: build.started)?.start ?? build.started
            durations[key, default: 0] += build.duration
            counts[key, default: 0] += 1
        }
        return durations
            .map { TimelineRow(start: $0.key, totalDuration: $0.value, count: counts[$0.key] ?? 0) }
            .sorted { $0.start < $1.start }
    }
}

enum Format {
    static func duration(_ seconds: TimeInterval) -> String {
        let total: Int = max(0, Int(seconds.rounded()))
        let hours: Int = total / 3600
        let minutes: Int = (total % 3600) / 60
        let secs: Int = total % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }

    static func stamp(_ date: Date) -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: date)
    }

    static func compact(_ seconds: TimeInterval) -> String {
        let total: Int = max(0, Int(seconds.rounded()))
        let hours: Int = total / 3600
        let minutes: Int = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h\(minutes)m"
        }
        return "\(minutes)m"
    }

    static func relative(_ date: Date, to now: Date) -> String {
        let seconds: TimeInterval = now.timeIntervalSince(date)
        if seconds < 60 {
            return "just now"
        }
        if seconds < 3600 {
            return "\(Int(seconds / 60))m ago"
        }
        if seconds < 86400 {
            return "\(Int(seconds / 3600))h ago"
        }
        return "\(Int(seconds / 86400))d ago"
    }
}
