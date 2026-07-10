import XCTest
@testable import XCBuildStats

final class BuildStoreTests: XCTestCase {
    private func tempPath() -> URL {
        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xcbs-db-\(UUID().uuidString).sqlite")
    }

    private func record(_ id: String, _ duration: TimeInterval, project: String = "P", clean: Bool = false) -> BuildRecord {
        let start: Date = Date(timeIntervalSince1970: 1_000_000)
        return BuildRecord(
            id: id,
            project: project,
            scheme: "S",
            title: clean ? "Clean P" : "Build P",
            started: start,
            stopped: start.addingTimeInterval(duration),
            succeeded: true,
            errors: 0,
            warnings: 3,
            status: "S"
        )
    }

    func testIngestDedupAndRoundTrip() throws {
        let url: URL = tempPath()
        defer { try? FileManager.default.removeItem(at: url) }
        let store: BuildStore = BuildStore(path: url.path)

        XCTAssertEqual(store.ingest([record("a", 10), record("b", 20)]).map(\.id), ["a", "b"])
        XCTAssertEqual(store.ingest([record("a", 10), record("c", 30)]).map(\.id), ["c"], "duplicate id must be ignored")

        let all: [BuildRecord] = store.allBuilds()
        XCTAssertEqual(all.count, 3)
        let a: BuildRecord? = all.first { $0.id == "a" }
        XCTAssertEqual(a?.duration, 10)
        XCTAssertEqual(a?.warnings, 3)
        XCTAssertEqual(a?.project, "P")
    }

    func testEventsDedupAndClear() throws {
        let url: URL = tempPath()
        defer { try? FileManager.default.removeItem(at: url) }
        let store: BuildStore = BuildStore(path: url.path)

        store.ingest([record("a", 10)])
        let event: BuildEvent = BuildEvent(id: "e1", type: BuildEventType.derivedDataDeleted, project: "P", timestamp: Date(timeIntervalSince1970: 2_000_000))
        store.insertEvent(event)
        store.insertEvent(event)
        XCTAssertEqual(store.allEvents().count, 1, "duplicate event id must be ignored")

        store.clear()
        XCTAssertEqual(store.allBuilds().count, 0)
        XCTAssertEqual(store.allEvents().count, 0)
    }

    func testPersistenceAcrossInstances() throws {
        let url: URL = tempPath()
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let store: BuildStore = BuildStore(path: url.path)
            store.ingest([record("a", 10)])
        }
        let reopened: BuildStore = BuildStore(path: url.path)
        XCTAssertEqual(reopened.allBuilds().count, 1, "data must survive a reopen")
    }
}
