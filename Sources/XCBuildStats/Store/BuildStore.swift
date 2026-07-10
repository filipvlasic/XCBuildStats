import Foundation
import SQLite3

private let sqliteTransient: sqlite3_destructor_type = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class BuildStore {
    private var db: OpaquePointer?
    let dbURL: URL

    init(path: String) {
        dbURL = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        open()
        createSchema()
    }

    convenience init() {
        let directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".xcbuildstats", isDirectory: true)
        self.init(path: directory.appendingPathComponent("db.sqlite").path)
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    private func open() {
        let flags: Int32 = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        if sqlite3_open_v2(dbURL.path, &db, flags, nil) != SQLITE_OK {
            NSLog("XCBuildStats: cannot open database at \(dbURL.path)")
        }
    }

    private func createSchema() {
        exec("""
        CREATE TABLE IF NOT EXISTS builds (
            id TEXT PRIMARY KEY,
            project TEXT NOT NULL,
            scheme TEXT,
            title TEXT,
            started REAL NOT NULL,
            stopped REAL NOT NULL,
            duration REAL NOT NULL,
            succeeded INTEGER NOT NULL,
            errors INTEGER NOT NULL,
            warnings INTEGER NOT NULL,
            status TEXT
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS events (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            project TEXT,
            timestamp REAL NOT NULL
        );
        """)
    }

    /// Returns the records that were actually inserted (already-known ids are ignored).
    @discardableResult
    func ingest(_ records: [BuildRecord]) -> [BuildRecord] {
        guard !records.isEmpty else {
            return []
        }
        let sql: String = """
        INSERT OR IGNORE INTO builds
        (id, project, scheme, title, started, stopped, duration, succeeded, errors, warnings, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer {
            sqlite3_finalize(statement)
        }
        exec("BEGIN TRANSACTION;")
        var inserted: [BuildRecord] = []
        for record in records {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bindText(statement, 1, record.id)
            bindText(statement, 2, record.project)
            bindText(statement, 3, record.scheme)
            bindText(statement, 4, record.title)
            sqlite3_bind_double(statement, 5, record.started.timeIntervalSince1970)
            sqlite3_bind_double(statement, 6, record.stopped.timeIntervalSince1970)
            sqlite3_bind_double(statement, 7, record.duration)
            sqlite3_bind_int(statement, 8, record.succeeded ? 1 : 0)
            sqlite3_bind_int(statement, 9, Int32(record.errors))
            sqlite3_bind_int(statement, 10, Int32(record.warnings))
            bindText(statement, 11, record.status)
            if sqlite3_step(statement) == SQLITE_DONE, sqlite3_changes(db) > 0 {
                inserted.append(record)
            }
        }
        exec("COMMIT;")
        return inserted
    }

    func allBuilds() -> [BuildRecord] {
        let sql: String = """
        SELECT id, project, scheme, title, started, stopped, succeeded, errors, warnings, status
        FROM builds ORDER BY started;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer {
            sqlite3_finalize(statement)
        }
        var result: [BuildRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let started: Double = sqlite3_column_double(statement, 4)
            let stopped: Double = sqlite3_column_double(statement, 5)
            let record: BuildRecord = BuildRecord(
                id: columnText(statement, 0) ?? "",
                project: columnText(statement, 1) ?? "Unknown",
                scheme: columnText(statement, 2),
                title: columnText(statement, 3),
                started: Date(timeIntervalSince1970: started),
                stopped: Date(timeIntervalSince1970: stopped),
                succeeded: sqlite3_column_int(statement, 6) != 0,
                errors: Int(sqlite3_column_int(statement, 7)),
                warnings: Int(sqlite3_column_int(statement, 8)),
                status: columnText(statement, 9)
            )
            result.append(record)
        }
        return result
    }

    func insertEvent(_ event: BuildEvent) {
        let sql: String = """
        INSERT OR IGNORE INTO events (id, type, project, timestamp)
        VALUES (?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer {
            sqlite3_finalize(statement)
        }
        bindText(statement, 1, event.id)
        bindText(statement, 2, event.type)
        bindText(statement, 3, event.project)
        sqlite3_bind_double(statement, 4, event.timestamp.timeIntervalSince1970)
        sqlite3_step(statement)
    }

    func allEvents() -> [BuildEvent] {
        let sql: String = "SELECT id, type, project, timestamp FROM events ORDER BY timestamp;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer {
            sqlite3_finalize(statement)
        }
        var result: [BuildEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let event: BuildEvent = BuildEvent(
                id: columnText(statement, 0) ?? "",
                type: columnText(statement, 1) ?? "",
                project: columnText(statement, 2),
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            )
            result.append(event)
        }
        return result
    }

    func clear() {
        exec("DELETE FROM builds;")
        exec("DELETE FROM events;")
    }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            _ = value.withCString { pointer in
                sqlite3_bind_text(statement, index, pointer, -1, sqliteTransient)
            }
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: pointer)
    }
}
