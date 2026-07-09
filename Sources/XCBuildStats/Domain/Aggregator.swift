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
