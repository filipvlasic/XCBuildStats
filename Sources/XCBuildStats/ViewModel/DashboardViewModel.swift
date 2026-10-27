import Foundation
import Observation
import AppKit

@Observable
final class DashboardViewModel {
    private let store: BuildStore = BuildStore()
    private let ioQueue: DispatchQueue = DispatchQueue(label: "com.filipvlasic.xcbuildstats.io")
    private let calendar: Calendar = .current
    private var watcher: DerivedDataWatcher?
    private var xcodebuildMonitor: XcodebuildMonitor?
    private var clockTimer: Timer?

    private(set) var builds: [BuildRecord] = []
    private(set) var events: [BuildEvent] = []
    private(set) var lastUpdated: Date?
    private(set) var now: Date = Date()
    private var knownFolders: Set<String> = []
    // Notification dedup is deliberately independent of DB insertion: clearing the
    // database (and re-ingesting the same manifests) or a concurrent `--report` run
    // inserting a build first must not create duplicate or swallowed notifications.
    private var seenBuildIds: Set<String> = []
    private var hasSeededNotifications: Bool = false

    var grouping: Grouping = .day {
        didSet {
            periodOffset = 0
        }
    }
    var periodOffset: Int = 0

    var sourceFilter: SourceFilter {
        get {
            return Preferences.shared.sourceFilter
        }
        set {
            Preferences.shared.sourceFilter = newValue
        }
    }

    init() {
        reload()
        startWatching()
        setCommandLineTracking(Preferences.shared.trackCommandLineBuilds)
        startClock()
    }

    var period: DateInterval {
        return Aggregator.periodInterval(grouping: grouping, now: now, offset: periodOffset, calendar: calendar)
    }

    var summary: PeriodSummary {
        return Aggregator.summary(buildsOnly, in: period)
    }

    var bars: [Bar] {
        return Aggregator.bars(buildsOnly, in: period, subComponent: grouping.subComponent, calendar: calendar)
    }

    var projectStats: [ProjectStat] {
        return Aggregator.projectStats(buildsOnly, in: period)
    }

    /// Each source's share of the chart bars; drawn stacked when showing all sources.
    var sourceBars: [SourceBar] {
        return Aggregator.sourceBars(buildsOnly, in: period, subComponent: grouping.subComponent, calendar: calendar)
    }

    var sourceStats: [SourceStat] {
        return Aggregator.sourceStats(buildsOnly, in: period)
    }

    private var included: [BuildRecord] {
        let excluded: Set<String> = Preferences.shared.excludedProjects
        let filter: SourceFilter = sourceFilter
        return builds.filter { !excluded.contains($0.project) && filter.includes($0.source) }
    }

    private var buildsOnly: [BuildRecord] {
        return included.filter { !$0.isClean }
    }

    private var cleansOnly: [BuildRecord] {
        return included.filter { $0.isClean }
    }

    var availableProjects: [String] {
        return Set(builds.map { $0.project }).sorted()
    }

    var databaseURL: URL {
        return store.dbURL
    }

    var derivedDataDeletionCount: Int {
        let excluded: Set<String> = Preferences.shared.excludedProjects
        return events.filter {
            $0.type == BuildEventType.derivedDataDeleted && !excluded.contains($0.project ?? "")
        }.count
    }

    var longestBuild: BuildRecord? {
        return Aggregator.builds(buildsOnly, in: period).max { $0.duration < $1.duration }
    }

    var cleanCount: Int {
        return Aggregator.builds(cleansOnly, in: period).count
    }

    var cleanTotalDuration: TimeInterval {
        return Aggregator.builds(cleansOnly, in: period).reduce(0) { $0 + $1.duration }
    }

    var totalBuildCount: Int {
        return buildsOnly.count
    }

    var totalCleanCount: Int {
        return cleansOnly.count
    }

    var hasAnyBuilds: Bool {
        return !buildsOnly.isEmpty
    }

    var lastBuildDate: Date? {
        return buildsOnly.map { $0.started }.max()
    }

    var previousPeriodDelta: Double? {
        return Aggregator.previousPeriodDelta(buildsOnly, grouping: grouping, now: now, offset: periodOffset, calendar: calendar)
    }

    var isCurrentPeriod: Bool {
        return periodOffset == 0
    }

    var canGoNext: Bool {
        return periodOffset < 0
    }

    var periodTitle: String {
        if isCurrentPeriod {
            switch grouping {
            case .day:
                return "today"
            case .week:
                return "this week"
            case .month:
                return "this month"
            case .year:
                return "this year"
            }
        }
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.calendar = calendar
        switch grouping {
        case .day:
            formatter.dateFormat = "EEEE, MMM d, yyyy"
            return formatter.string(from: period.start)
        case .week:
            let week: Int = calendar.component(.weekOfYear, from: period.start)
            formatter.dateFormat = "MMM d"
            let start: String = formatter.string(from: period.start)
            let lastDay: Date = calendar.date(byAdding: .day, value: -1, to: period.end) ?? period.end
            let end: String = formatter.string(from: lastDay)
            return "W\(week) · \(start) – \(end)"
        case .month:
            formatter.dateFormat = "LLLL yyyy"
            return formatter.string(from: period.start)
        case .year:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: period.start)
        }
    }

    var menuBarSummary: String {
        let text: String
        switch Preferences.shared.menuBarDisplay {
        case .currentPeriod:
            let currentPeriod: DateInterval = Aggregator.periodInterval(grouping: grouping, now: now, offset: 0, calendar: calendar)
            text = Format.compact(Aggregator.summary(buildsOnly, in: currentPeriod).totalDuration)
        case .todayTotal:
            let dayStart: Date = calendar.startOfDay(for: now)
            let duration: TimeInterval = buildsOnly
                .filter { $0.started >= dayStart }
                .reduce(0) { $0 + $1.duration }
            text = Format.compact(duration)
        }
        // Pad to a constant character count so the menu bar item never changes
        // width (which would otherwise reposition the popover).
        let minimumWidth: Int = 5
        guard text.count < minimumWidth else {
            return text
        }
        return String(repeating: " ", count: minimumWidth - text.count) + text
    }

    func goPrevious() {
        periodOffset -= 1
    }

    func goNext() {
        guard canGoNext else {
            return
        }
        periodOffset += 1
    }

    func goToCurrent() {
        periodOffset = 0
    }

    func clearDatabase() {
        ioQueue.async { [weak self] in
            guard let self else {
                return
            }
            self.store.clear()
            let all: [BuildRecord] = self.store.allBuilds()
            let allEvents: [BuildEvent] = self.store.allEvents()
            DispatchQueue.main.async {
                self.builds = all
                self.events = allEvents
                self.now = Date()
                self.lastUpdated = Date()
            }
        }
    }

    func exportCSV() {
        Exporter.exportCSV(builds: builds)
    }

    func setCommandLineTracking(_ enabled: Bool) {
        guard enabled else {
            xcodebuildMonitor?.stop()
            xcodebuildMonitor = nil
            return
        }
        guard xcodebuildMonitor == nil else {
            return
        }
        let monitor: XcodebuildMonitor = XcodebuildMonitor { [weak self] run in
            self?.ingest(run)
        }
        monitor.start()
        xcodebuildMonitor = monitor
    }

    private func ingest(_ run: XcodebuildRun) {
        ioQueue.async { [weak self] in
            guard let self else {
                return
            }
            self.store.ingest(run.buildRecords())
            self.reload()
        }
    }

    func reload() {
        ioQueue.async { [weak self] in
            guard let self else {
                return
            }
            let scanned: [BuildRecord] = ManifestScanner.scan()
            self.store.ingest(scanned)
            self.store.reconcileOutcomes(scanned)
            self.detectDerivedDataDeletions()
            let all: [BuildRecord] = self.store.allBuilds()
            let allEvents: [BuildEvent] = self.store.allEvents()
            DispatchQueue.main.async {
                self.builds = all
                self.events = allEvents
                self.now = Date()
                self.lastUpdated = Date()
                self.notifyIfNeeded(all)
            }
        }
    }

    private func notifyIfNeeded(_ current: [BuildRecord]) {
        let newBuilds: [BuildRecord] = current.filter { !seenBuildIds.contains($0.id) }
        seenBuildIds.formUnion(newBuilds.map { $0.id })
        // The first reload of a launch is backfill of history, never a fresh finish.
        guard hasSeededNotifications else {
            hasSeededNotifications = true
            return
        }
        guard Preferences.shared.notifyOnBuildEnd else {
            return
        }
        let excluded: Set<String> = Preferences.shared.excludedProjects
        let threshold: TimeInterval = Preferences.shared.effectiveNotifyThreshold
        // Only builds someone sat waiting for in Xcode; an agent's builds would
        // otherwise post a stream of alerts.
        for build in newBuilds
        where build.source == .xcode && !excluded.contains(build.project)
            && BuildNotifier.shouldNotify(build, threshold: threshold, now: Date()) {
            BuildNotifier.notify(build)
        }
    }

    private func detectDerivedDataDeletions() {
        let current: Set<String> = confirmedProjectFolders()
        for event in ManifestScanner.deletionEvents(previous: knownFolders, current: current, at: Date()) {
            store.insertEvent(event)
        }
        knownFolders = current
    }

    /// A single empty/unreadable read (transient FS glitch during heavy Xcode churn)
    /// must not be misread as "everything was deleted" — but a real full wipe must
    /// still be recorded, so a suspicious read is confirmed by re-reading.
    private func confirmedProjectFolders() -> Set<String> {
        var read: Set<String> = ManifestScanner.projectFolderNames() ?? []
        guard read.isEmpty, !knownFolders.isEmpty else {
            return read
        }
        for _ in 0..<2 {
            Thread.sleep(forTimeInterval: 0.25)
            read = ManifestScanner.projectFolderNames() ?? []
            if !read.isEmpty {
                return read
            }
        }
        return read
    }

    private func startWatching() {
        let watcher: DerivedDataWatcher = DerivedDataWatcher(path: ManifestScanner.derivedDataURL.path) { [weak self] in
            self?.reload()
        }
        watcher.start()
        self.watcher = watcher
    }

    private func startClock() {
        scheduleMidnightRefresh()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.now = Date()
            self?.reload()
            self?.scheduleMidnightRefresh()
        }
    }

    private func scheduleMidnightRefresh() {
        clockTimer?.invalidate()
        let tomorrow: Date = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let nextMidnight: Date = calendar.startOfDay(for: tomorrow)
        let timer: Timer = Timer(fire: nextMidnight, interval: 0, repeats: false) { [weak self] _ in
            self?.now = Date()
            self?.scheduleMidnightRefresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }
}
