import Foundation
import os

public enum DiagnosticCategory: String, Codable, CaseIterable {
    case lifecycle
    case settings
    case bluetooth
    case proximity
    case screen
    case wake
    case system
    case ui
}

public enum DiagnosticLevel: String, Codable {
    case info
    case warning
    case error
}

public enum DiagnosticOutcome: String, Codable {
    case observed
    case pending
    case success
    case skipped
    case failure
}

/// One stable, machine-readable diagnostic record.
///
/// `code` and `correlationID` are deliberately separate from the Korean
/// presentation text. Support can group a request and its later confirmation
/// without parsing localized strings, while the menu can still show `message`.
public struct DiagnosticEvent: Codable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let sessionID: String
    public let category: DiagnosticCategory
    public let level: DiagnosticLevel
    public let code: String
    public let outcome: DiagnosticOutcome
    public let correlationID: String?
    public let message: String
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        sessionID: String,
        category: DiagnosticCategory,
        level: DiagnosticLevel,
        code: String,
        outcome: DiagnosticOutcome,
        correlationID: String? = nil,
        message: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sessionID = sessionID
        self.category = category
        self.level = level
        self.code = code
        self.outcome = outcome
        self.correlationID = correlationID
        self.message = message
        self.metadata = metadata
    }

    /// Compact form used by Unified Logging and copied support diagnostics.
    public var line: String {
        var fields = [
            "session=\(sessionID)",
            "category=\(category.rawValue)",
            "event=\(code)",
            "outcome=\(outcome.rawValue)"
        ]
        if let correlationID {
            fields.append("correlation=\(correlationID)")
        }
        for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
            fields.append("\(key)=\(value)")
        }
        fields.append("message=\"\(Self.singleLine(message))\"")
        return fields.joined(separator: " ")
    }

    private static func singleLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\"", with: "'")
    }
}

/// Unified Logging + durable SQLite diagnostics.
///
/// The unified log is convenient for live inspection, but `.info` records are
/// not guaranteed to remain on disk. Operational state transitions therefore
/// also go to `~/Library/Application Support/AutoLock/diagnostics.sqlite3`.
/// The database lives outside the replaceable `.app` bundle, so application
/// updates preserve it. Retention is bounded by age and row count. Callers must
/// only put non-secret values in metadata; passwords and full device identifiers
/// are intentionally never accepted implicitly.
public enum AppLog {
    public static let subsystem = "com.local.autolock"
    public static let sessionID = String(UUID().uuidString.prefix(8)).lowercased()

    public static let lifecycle = Logger(subsystem: subsystem, category: DiagnosticCategory.lifecycle.rawValue)
    public static let settings = Logger(subsystem: subsystem, category: DiagnosticCategory.settings.rawValue)
    public static let bluetooth = Logger(subsystem: subsystem, category: DiagnosticCategory.bluetooth.rawValue)
    public static let proximity = Logger(subsystem: subsystem, category: DiagnosticCategory.proximity.rawValue)
    public static let screen = Logger(subsystem: subsystem, category: DiagnosticCategory.screen.rawValue)
    public static let wake = Logger(subsystem: subsystem, category: DiagnosticCategory.wake.rawValue)
    public static let system = Logger(subsystem: subsystem, category: DiagnosticCategory.system.rawValue)
    public static let ui = Logger(subsystem: subsystem, category: DiagnosticCategory.ui.rawValue)

    private static let sink = DiagnosticLogSink()

    @discardableResult
    public static func record(
        _ category: DiagnosticCategory,
        level: DiagnosticLevel = .info,
        code: String,
        outcome: DiagnosticOutcome,
        correlationID: String? = nil,
        message: String,
        metadata: [String: String] = [:]
    ) -> DiagnosticEvent {
        let event = DiagnosticEvent(
            sessionID: sessionID,
            category: category,
            level: level,
            code: code,
            outcome: outcome,
            correlationID: correlationID,
            message: message,
            metadata: metadata
        )

        let logger = logger(for: category)
        switch level {
        case .info:
            logger.info("\(event.line, privacy: .public)")
        case .warning:
            logger.warning("\(event.line, privacy: .public)")
        case .error:
            logger.error("\(event.line, privacy: .public)")
        }
        sink.append(event)
        return event
    }

    /// Persisted records across app sessions, newest first. If SQLite is
    /// unavailable, this falls back to the current process's in-memory records.
    public static func recentEvents(limit: Int = 20) -> [DiagnosticEvent] {
        sink.recent(limit: max(0, limit))
    }

    public static var logDatabaseURL: URL {
        sink.databaseURL
    }

    public static var isPersistentStoreAvailable: Bool {
        sink.isPersistentStoreAvailable
    }

    public static var persistentStoreFailure: String? {
        sink.persistentStoreFailure
    }

    public static func containsPersistedEvent(id: UUID) -> Bool {
        sink.containsPersistedEvent(id: id)
    }

    private static func logger(for category: DiagnosticCategory) -> Logger {
        switch category {
        case .lifecycle: return lifecycle
        case .settings: return settings
        case .bluetooth: return bluetooth
        case .proximity: return proximity
        case .screen: return screen
        case .wake: return wake
        case .system: return system
        case .ui: return ui
        }
    }
}
