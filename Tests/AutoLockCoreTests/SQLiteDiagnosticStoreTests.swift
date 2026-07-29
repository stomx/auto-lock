import Foundation
import Testing
@testable import AutoLockCore

@Suite struct SQLiteDiagnosticStoreTests {
    private func temporaryDatabase() -> (directory: URL, database: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("autolock-sqlite-tests-\(UUID().uuidString)", isDirectory: true)
        return (directory, directory.appendingPathComponent("diagnostics.sqlite3"))
    }

    private func event(
        index: Int,
        timestamp: Date = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)),
        correlationID: String? = nil
    ) -> DiagnosticEvent {
        DiagnosticEvent(
            id: UUID(),
            timestamp: timestamp,
            sessionID: "session-\(index / 2)",
            category: .screen,
            level: index.isMultiple(of: 2) ? .info : .error,
            code: "event_\(index)",
            outcome: index.isMultiple(of: 2) ? .success : .failure,
            correlationID: correlationID,
            message: "진단 이벤트 \(index)",
            metadata: ["index": String(index), "state": "locked"]
        )
    }

    @Test func productionDatabaseLocationIsOutsideReplaceableAppBundle() {
        let path = AppLog.logDatabaseURL.standardizedFileURL.path
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.standardizedFileURL.path
        #expect(path.hasPrefix(applicationSupport))
        #expect(path.hasSuffix("/AutoLock/diagnostics.sqlite3"))
        #expect(!path.hasPrefix(Bundle.main.bundleURL.standardizedFileURL.path + "/"))
    }

    @Test func schemaAndEventsSurviveStoreReopen() throws {
        let paths = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let original = event(index: 1, correlationID: "corr-1")

        do {
            let store = try SQLiteDiagnosticStore(databaseURL: paths.database)
            #expect(try store.schemaUserVersion() == SQLiteDiagnosticStore.schemaVersion)
            try store.insert(original)
            #expect(try store.contains(id: original.id))
        }

        do {
            let reopened = try SQLiteDiagnosticStore(databaseURL: paths.database)
            let events = try reopened.recent(limit: 10)
            #expect(events == [original])
            #expect(try reopened.count() == 1)
        }
    }

    @Test func countRetentionKeepsNewestRows() throws {
        let paths = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let base = Date(timeIntervalSince1970: 1_000_000)
        let store = try SQLiteDiagnosticStore(
            databaseURL: paths.database,
            maximumEventCount: 3,
            now: { base.addingTimeInterval(10) }
        )
        for index in 0..<5 {
            try store.insert(event(
                index: index,
                timestamp: base.addingTimeInterval(TimeInterval(index))
            ))
        }

        try store.prune(referenceDate: base.addingTimeInterval(10))
        #expect(try store.count() == 3)
        #expect(try store.recent(limit: 10).map(\.code) == ["event_4", "event_3", "event_2"])
        #expect(try store.recent(limit: 0).isEmpty)
    }

    @Test func ageRetentionRemovesExpiredRows() throws {
        let paths = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let reference = Date(timeIntervalSince1970: 2_000_000)
        let store = try SQLiteDiagnosticStore(
            databaseURL: paths.database,
            maximumEventCount: 10,
            retentionDays: 1,
            now: { reference }
        )
        try store.insert(event(index: 0, timestamp: reference.addingTimeInterval(-90_000)))
        let fresh = event(index: 1, timestamp: reference)
        try store.insert(fresh)

        try store.prune(referenceDate: reference)
        #expect(try store.recent(limit: 10) == [fresh])
    }

    @Test func legacyJSONLImportsThenRemovesSource() throws {
        let paths = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        try FileManager.default.createDirectory(at: paths.directory, withIntermediateDirectories: true)
        let legacy = paths.directory.appendingPathComponent("events.jsonl")
        let events = [event(index: 1), event(index: 2)]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let lines = try events.map { event in
            String(decoding: try encoder.encode(event), as: UTF8.self)
        }.joined(separator: "\n") + "\n"
        try lines.write(to: legacy, atomically: true, encoding: .utf8)

        let store = try SQLiteDiagnosticStore(databaseURL: paths.database)
        #expect(try store.importLegacyJSONL(files: [legacy]) == 2)
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        let imported = try store.recent(limit: 10)
        #expect(imported.map(\.code) == ["event_2", "event_1"])
        #expect(Set(imported.map(\.id)) == Set(events.map(\.id)))
        #expect(imported.allSatisfy { $0.metadata["state"] == "locked" })
    }

    @Test func malformedLegacyJSONLRollsBackAndPreservesSource() throws {
        let paths = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        try FileManager.default.createDirectory(at: paths.directory, withIntermediateDirectories: true)
        let legacy = paths.directory.appendingPathComponent("events.jsonl")
        try "{\"not\":\"an event\"}\n".write(to: legacy, atomically: true, encoding: .utf8)
        let store = try SQLiteDiagnosticStore(databaseURL: paths.database)

        #expect(throws: SQLiteDiagnosticStoreError.self) {
            try store.importLegacyJSONL(files: [legacy])
        }
        #expect(FileManager.default.fileExists(atPath: legacy.path))
        #expect(try store.count() == 0)
    }

    @Test func databaseUsesPrivatePermissions() throws {
        let paths = temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        _ = try SQLiteDiagnosticStore(databaseURL: paths.database)
        let attributes = try FileManager.default.attributesOfItem(atPath: paths.database.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        #expect(permissions == 0o600)
    }
}
