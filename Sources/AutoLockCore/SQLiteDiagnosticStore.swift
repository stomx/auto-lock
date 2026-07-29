import Foundation
import SQLite3

enum SQLiteDiagnosticStoreError: Error, CustomStringConvertible {
    case open(path: String, message: String)
    case sqlite(operation: String, code: Int32, message: String)
    case invalidSchemaVersion(Int32)
    case encodeMetadata
    case malformedLegacyRecord(URL, line: Int)

    var description: String {
        switch self {
        case .open(let path, let message):
            return "database open failed path=\(path) message=\(message)"
        case .sqlite(let operation, let code, let message):
            return "sqlite operation failed operation=\(operation) code=\(code) message=\(message)"
        case .invalidSchemaVersion(let version):
            return "unsupported diagnostics schema version=\(version)"
        case .encodeMetadata:
            return "diagnostic metadata JSON encoding failed"
        case .malformedLegacyRecord(let url, let line):
            return "legacy JSONL migration failed file=\(url.lastPathComponent) line=\(line)"
        }
    }
}

/// Native SQLite boundary. The schema is deliberately append-oriented and
/// versioned so future app builds can migrate it in place without replacing the
/// database. SQLite's WAL mode keeps UI writes short and crash-safe.
final class SQLiteDiagnosticStore {
    static let schemaVersion: Int32 = 1

    let databaseURL: URL
    private let maximumEventCount: Int
    private let retentionSeconds: TimeInterval
    private let now: () -> Date
    private var database: OpaquePointer?
    private var insertionsSincePrune = 0

    init(
        databaseURL: URL,
        maximumEventCount: Int = 25_000,
        retentionDays: Int = 90,
        now: @escaping () -> Date = Date.init
    ) throws {
        self.databaseURL = databaseURL
        self.maximumEventCount = max(1, maximumEventCount)
        self.retentionSeconds = TimeInterval(max(1, retentionDays) * 86_400)
        self.now = now

        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(databaseURL.path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "no sqlite handle"
            if let handle { sqlite3_close(handle) }
            throw SQLiteDiagnosticStoreError.open(path: databaseURL.path, message: message)
        }
        database = handle

        do {
            try execute("PRAGMA busy_timeout = 2000", operation: "configure busy timeout")
            try execute("PRAGMA journal_mode = WAL", operation: "enable WAL")
            try execute("PRAGMA synchronous = NORMAL", operation: "configure sync")
            try execute("PRAGMA foreign_keys = ON", operation: "enable foreign keys")
            try migrateSchema()
            try setPrivatePermissions()
        } catch {
            sqlite3_close(handle)
            database = nil
            throw error
        }
    }

    deinit {
        if let database {
            sqlite3_wal_checkpoint_v2(database, nil, SQLITE_CHECKPOINT_PASSIVE, nil, nil)
            sqlite3_close(database)
        }
    }

    func insert(_ event: DiagnosticEvent, pruneIfNeeded: Bool = true) throws {
        let metadataData = try JSONSerialization.data(
            withJSONObject: event.metadata,
            options: [.sortedKeys]
        )
        guard let metadataJSON = String(data: metadataData, encoding: .utf8) else {
            throw SQLiteDiagnosticStoreError.encodeMetadata
        }

        let sql = """
        INSERT OR IGNORE INTO diagnostic_events (
            id, timestamp, session_id, category, level, code, outcome,
            correlation_id, message, metadata_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        let statement = try prepare(sql, operation: "prepare event insert")
        defer { sqlite3_finalize(statement) }

        try bind(event.id.uuidString, at: 1, to: statement)
        try bind(event.timestamp.timeIntervalSince1970, at: 2, to: statement)
        try bind(event.sessionID, at: 3, to: statement)
        try bind(event.category.rawValue, at: 4, to: statement)
        try bind(event.level.rawValue, at: 5, to: statement)
        try bind(event.code, at: 6, to: statement)
        try bind(event.outcome.rawValue, at: 7, to: statement)
        if let correlationID = event.correlationID {
            try bind(correlationID, at: 8, to: statement)
        } else {
            sqlite3_bind_null(statement, 8)
        }
        try bind(event.message, at: 9, to: statement)
        try bind(metadataJSON, at: 10, to: statement)
        try stepDone(statement, operation: "insert event")

        if pruneIfNeeded {
            insertionsSincePrune += 1
            try prune(referenceDate: now(), performVacuum: insertionsSincePrune >= 100)
            if insertionsSincePrune >= 100 {
                insertionsSincePrune = 0
            }
        }
    }

    func recent(limit: Int) throws -> [DiagnosticEvent] {
        guard limit > 0 else { return [] }
        let sql = """
        SELECT id, timestamp, session_id, category, level, code, outcome,
               correlation_id, message, metadata_json
        FROM diagnostic_events
        ORDER BY timestamp DESC, rowid DESC
        LIMIT ?
        """
        let statement = try prepare(sql, operation: "prepare recent event query")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, sqlite3_int64(limit))

        var events: [DiagnosticEvent] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else {
                throw sqliteError(operation: "query recent events", code: result)
            }
            if let event = decodeEvent(statement) {
                events.append(event)
            }
        }
        return events
    }

    func contains(id: UUID) throws -> Bool {
        let statement = try prepare(
            "SELECT 1 FROM diagnostic_events WHERE id = ? LIMIT 1",
            operation: "prepare event existence query"
        )
        defer { sqlite3_finalize(statement) }
        try bind(id.uuidString, at: 1, to: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW { return true }
        if result == SQLITE_DONE { return false }
        throw sqliteError(operation: "query event existence", code: result)
    }

    func count() throws -> Int {
        let statement = try prepare(
            "SELECT COUNT(*) FROM diagnostic_events",
            operation: "prepare event count"
        )
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else {
            throw sqliteError(operation: "count events", code: result)
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func schemaUserVersion() throws -> Int32 {
        let statement = try prepare("PRAGMA user_version", operation: "read schema version")
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else {
            throw sqliteError(operation: "read schema version", code: result)
        }
        return sqlite3_column_int(statement, 0)
    }

    /// Imports every legacy JSONL record transactionally per file. A malformed
    /// file remains in place for manual recovery; successfully imported files
    /// are removed only after all their records are durable in SQLite.
    func importLegacyJSONL(files: [URL]) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var imported = 0

        for file in files where FileManager.default.fileExists(atPath: file.path) {
            let contents = try String(contentsOf: file, encoding: .utf8)
            try execute("BEGIN IMMEDIATE", operation: "begin legacy import")
            do {
                for (offset, line) in contents.split(whereSeparator: \.isNewline).enumerated() {
                    guard let data = String(line).data(using: .utf8),
                          let event = try? decoder.decode(DiagnosticEvent.self, from: data) else {
                        throw SQLiteDiagnosticStoreError.malformedLegacyRecord(file, line: offset + 1)
                    }
                    try insert(event, pruneIfNeeded: false)
                    imported += 1
                }
                try execute("COMMIT", operation: "commit legacy import")
                try prune()
                try FileManager.default.removeItem(at: file)
            } catch {
                try? execute("ROLLBACK", operation: "rollback legacy import")
                throw error
            }
        }
        return imported
    }

    func prune(referenceDate: Date = Date(), performVacuum: Bool = true) throws {
        let oldestAllowed = referenceDate.timeIntervalSince1970 - retentionSeconds
        let ageStatement = try prepare(
            "DELETE FROM diagnostic_events WHERE timestamp < ?",
            operation: "prepare age retention"
        )
        try bind(oldestAllowed, at: 1, to: ageStatement)
        do {
            try stepDone(ageStatement, operation: "apply age retention")
            sqlite3_finalize(ageStatement)
        } catch {
            sqlite3_finalize(ageStatement)
            throw error
        }

        let countStatement = try prepare(
            """
            DELETE FROM diagnostic_events
            WHERE rowid IN (
                SELECT rowid FROM diagnostic_events
                ORDER BY timestamp DESC, rowid DESC
                LIMIT -1 OFFSET ?
            )
            """,
            operation: "prepare count retention"
        )
        sqlite3_bind_int64(countStatement, 1, sqlite3_int64(maximumEventCount))
        do {
            try stepDone(countStatement, operation: "apply count retention")
            sqlite3_finalize(countStatement)
        } catch {
            sqlite3_finalize(countStatement)
            throw error
        }
        if performVacuum {
            try execute("PRAGMA incremental_vacuum(100)", operation: "incremental vacuum")
        }
    }

    private func migrateSchema() throws {
        let version = try schemaUserVersion()
        switch version {
        case 0:
            try execute(
                "PRAGMA auto_vacuum = INCREMENTAL",
                operation: "configure incremental auto vacuum"
            )
            try execute("VACUUM", operation: "initialize auto vacuum")
            try execute(
                """
                CREATE TABLE diagnostic_events (
                    id TEXT PRIMARY KEY NOT NULL,
                    timestamp REAL NOT NULL,
                    session_id TEXT NOT NULL,
                    category TEXT NOT NULL,
                    level TEXT NOT NULL,
                    code TEXT NOT NULL,
                    outcome TEXT NOT NULL,
                    correlation_id TEXT,
                    message TEXT NOT NULL,
                    metadata_json TEXT NOT NULL
                )
                """,
                operation: "create diagnostic events table"
            )
            try execute(
                "CREATE INDEX idx_diagnostic_events_timestamp ON diagnostic_events(timestamp DESC)",
                operation: "create timestamp index"
            )
            try execute(
                "CREATE INDEX idx_diagnostic_events_session ON diagnostic_events(session_id, timestamp)",
                operation: "create session index"
            )
            try execute(
                "CREATE INDEX idx_diagnostic_events_correlation ON diagnostic_events(correlation_id) WHERE correlation_id IS NOT NULL",
                operation: "create correlation index"
            )
            try execute(
                "PRAGMA user_version = \(Self.schemaVersion)",
                operation: "write schema version"
            )
        case Self.schemaVersion:
            break
        default:
            throw SQLiteDiagnosticStoreError.invalidSchemaVersion(version)
        }
    }

    private func decodeEvent(_ statement: OpaquePointer) -> DiagnosticEvent? {
        guard
            let id = UUID(uuidString: text(statement, column: 0)),
            let category = DiagnosticCategory(rawValue: text(statement, column: 3)),
            let level = DiagnosticLevel(rawValue: text(statement, column: 4)),
            let outcome = DiagnosticOutcome(rawValue: text(statement, column: 6))
        else { return nil }

        let metadataString = text(statement, column: 9)
        let metadata: [String: String]
        if let data = metadataString.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            metadata = decoded
        } else {
            metadata = [:]
        }
        let correlation: String? = sqlite3_column_type(statement, 7) == SQLITE_NULL
            ? nil
            : text(statement, column: 7)

        return DiagnosticEvent(
            id: id,
            timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
            sessionID: text(statement, column: 2),
            category: category,
            level: level,
            code: text(statement, column: 5),
            outcome: outcome,
            correlationID: correlation,
            message: text(statement, column: 8),
            metadata: metadata
        )
    }

    private func execute(_ sql: String, operation: String) throws {
        guard let database else {
            throw SQLiteDiagnosticStoreError.open(path: databaseURL.path, message: "database is closed")
        }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw SQLiteDiagnosticStoreError.sqlite(
                operation: operation,
                code: result,
                message: message
            )
        }
    }

    private func prepare(_ sql: String, operation: String) throws -> OpaquePointer {
        guard let database else {
            throw SQLiteDiagnosticStoreError.open(path: databaseURL.path, message: "database is closed")
        }
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw sqliteError(operation: operation, code: result)
        }
        return statement
    }

    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let result = sqlite3_bind_text(statement, index, value, -1, transient)
        guard result == SQLITE_OK else {
            throw sqliteError(operation: "bind text at \(index)", code: result)
        }
    }

    private func bind(_ value: Double, at index: Int32, to statement: OpaquePointer) throws {
        let result = sqlite3_bind_double(statement, index, value)
        guard result == SQLITE_OK else {
            throw sqliteError(operation: "bind double at \(index)", code: result)
        }
    }

    private func stepDone(_ statement: OpaquePointer, operation: String) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw sqliteError(operation: operation, code: result)
        }
    }

    private func sqliteError(operation: String, code: Int32) -> SQLiteDiagnosticStoreError {
        let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "database is closed"
        return .sqlite(operation: operation, code: code, message: message)
    }

    private func text(_ statement: OpaquePointer, column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    private func setPrivatePermissions() throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: databaseURL.path
        )
    }
}

final class DiagnosticLogSink: @unchecked Sendable {
    private let lock = NSLock()
    private var memory: [DiagnosticEvent] = []
    private let memoryLimit = 200
    let databaseURL: URL
    private var store: SQLiteDiagnosticStore?
    private(set) var persistentStoreFailure: String?

    init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        databaseURL = applicationSupport
            .appendingPathComponent("AutoLock", isDirectory: true)
            .appendingPathComponent("diagnostics.sqlite3")

        let processName = ProcessInfo.processInfo.processName
        let shouldPersist = Bundle.main.bundleURL.pathExtension != "xctest"
            && !processName.contains("PackageTests")
            && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
            && ProcessInfo.processInfo.environment["AUTOLOCK_DISABLE_PERSISTENT_LOGGING"] != "1"
        guard shouldPersist else { return }

        do {
            let store = try SQLiteDiagnosticStore(databaseURL: databaseURL)
            self.store = store
            do {
                let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
                let legacyDirectory = library?.appendingPathComponent("Logs/AutoLock", isDirectory: true)
                let legacyNames = [
                    "events.3.jsonl", "events.2.jsonl", "events.1.jsonl", "events.jsonl"
                ]
                let legacyFiles = legacyNames.compactMap { legacyDirectory?.appendingPathComponent($0) }
                _ = try store.importLegacyJSONL(files: legacyFiles)
                try store.prune()
            } catch {
                // A legacy file must not take the new database offline. Keep
                // logging to SQLite and surface the migration problem in UI.
                persistentStoreFailure = "legacy migration: \(error)"
            }
        } catch {
            persistentStoreFailure = String(describing: error)
            store = nil
        }
    }

    var isPersistentStoreAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return store != nil
    }

    func append(_ event: DiagnosticEvent) {
        lock.lock()
        defer { lock.unlock() }

        memory.append(event)
        if memory.count > memoryLimit {
            memory.removeFirst(memory.count - memoryLimit)
        }
        guard let store else { return }
        do {
            try store.insert(event)
        } catch {
            persistentStoreFailure = String(describing: error)
        }
    }

    func recent(limit: Int) -> [DiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        if let store {
            do {
                return try store.recent(limit: limit)
            } catch {
                persistentStoreFailure = String(describing: error)
            }
        }
        return Array(memory.suffix(limit).reversed())
    }

    func containsPersistedEvent(id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let store else { return false }
        do {
            return try store.contains(id: id)
        } catch {
            persistentStoreFailure = String(describing: error)
            return false
        }
    }
}
