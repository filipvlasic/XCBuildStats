import Foundation

enum Reporter {
    static func runAndExit() -> Never {
        let store: BuildStore = BuildStore()
        let scanned: [BuildRecord] = ManifestScanner.scan()
        let inserted: [BuildRecord] = store.ingest(scanned)
        let all: [BuildRecord] = store.allBuilds()

        print("XCBuildStats")
        print("Database:    \(store.dbURL.path)")
        print("DerivedData: \(ManifestScanner.derivedDataURL.path)")
        print("Manifests: \(scanned.count) build(s) · newly stored: \(inserted.count) · total in database: \(all.count)")
        print("")

        guard !all.isEmpty else {
            print("No builds recorded.")
            exit(0)
        }

        let builds: [BuildRecord] = all.filter { !$0.isClean }
        let cleans: [BuildRecord] = all.filter { $0.isClean }

        if let longest: BuildRecord = builds.max(by: { $0.duration < $1.duration }) {
            let formatter: DateFormatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            print("Longest build: \(Format.duration(longest.duration)) · \(longest.project) · \(formatter.string(from: longest.started))")
        }
        if !cleans.isEmpty {
            let cleanTotal: TimeInterval = cleans.reduce(0) { $0 + $1.duration }
            print("Clean actions: \(cleans.count) · total \(Format.duration(cleanTotal))")
        }
        if !builds.isEmpty {
            let failedCount: Int = builds.filter { !$0.succeeded }.count
            let percent: Int = Int((Double(builds.count - failedCount) / Double(builds.count) * 100).rounded())
            print("Build success: \(builds.count - failedCount) of \(builds.count) succeeded (\(failedCount) failed, \(percent)%)")
        }
        print("")

        printGroup(title: "BY DAY", builds: builds, grouping: .day, limit: 30)
        printGroup(title: "BY WEEK", builds: builds, grouping: .week, limit: 26)
        printGroup(title: "BY MONTH", builds: builds, grouping: .month, limit: 24)
        printGroup(title: "BY YEAR", builds: builds, grouping: .year, limit: 10)

        let deletions: [BuildEvent] = store.allEvents().filter { $0.type == BuildEventType.derivedDataDeleted }
        print("── DERIVED DATA DELETIONS (observed while app running) ──")
        if deletions.isEmpty {
            print("  none")
        } else {
            let formatter: DateFormatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            for deletion in deletions {
                print("  \(formatter.string(from: deletion.timestamp))  \(deletion.project ?? "")")
            }
        }
        print("")

        exit(0)
    }

    private static func printGroup(title: String, builds: [BuildRecord], grouping: Grouping, limit: Int) {
        print("── \(title) ──")
        let rows: [TimelineRow] = Array(Aggregator.timeline(builds, grouping: grouping).suffix(limit))
        let formatter: DateFormatter = DateFormatter()
        switch grouping {
        case .day, .week:
            formatter.dateFormat = "yyyy-MM-dd"
        case .month:
            formatter.dateFormat = "yyyy-MM"
        case .year:
            formatter.dateFormat = "yyyy"
        }
        for row in rows {
            let dateString: String = formatter.string(from: row.start)
            let average: TimeInterval = row.count > 0 ? row.totalDuration / Double(row.count) : 0
            let line: String = "  "
                + pad(dateString, 12)
                + "total " + pad(Format.duration(row.totalDuration), 11)
                + "avg " + pad(Format.duration(average), 10)
                + "(\(row.count) \(row.count == 1 ? "build" : "builds"))"
            print(line)
        }
        print("")
    }

    private static func pad(_ string: String, _ width: Int) -> String {
        if string.count >= width {
            return string
        }
        return string + String(repeating: " ", count: width - string.count)
    }
}
