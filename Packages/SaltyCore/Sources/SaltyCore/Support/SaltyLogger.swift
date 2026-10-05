//
//  SaltyLogger.swift
//  SaltyCore
//
//  SaltyCore's logging type: a typealias for `os.Logger` on Apple platforms (unchanged behaviour),
//  and a small stderr fallback where OSLog doesn't exist (Windows, Linux, Android), so call sites
//  need no platform guards. Not swift-log, to avoid a dependency for a few lines of fallback.
//

#if canImport(OSLog)
import OSLog

/// `os.Logger` itself on Apple platforms.
typealias SaltyLogger = os.Logger

#else
import Foundation

/// Stderr-backed stand-in for `os.Logger` on platforms without unified logging.
/// Levels mirror `os.Logger`'s so call sites are source-compatible. No privacy redaction: output
/// goes to the process's own stderr, not a shared system log.
struct SaltyLogger: Sendable {
    private let subsystem: String
    private let category: String

    init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
    }

    func trace(_ message: @autoclosure () -> String) { emit("TRACE", message()) }
    func debug(_ message: @autoclosure () -> String) { emit("DEBUG", message()) }
    func info(_ message: @autoclosure () -> String) { emit("INFO", message()) }
    func notice(_ message: @autoclosure () -> String) { emit("NOTICE", message()) }
    func warning(_ message: @autoclosure () -> String) { emit("WARNING", message()) }
    func error(_ message: @autoclosure () -> String) { emit("ERROR", message()) }
    func critical(_ message: @autoclosure () -> String) { emit("CRITICAL", message()) }
    func fault(_ message: @autoclosure () -> String) { emit("FAULT", message()) }

    /// Best-effort: a log line that can't be written is dropped. The throwing `write(contentsOf:)`
    /// with `try?`, not the legacy `write(_:)`, which `try!`s and traps when the write fails. A
    /// Windows GUI app started from Explorer has no stderr (Foundation's handle comes from
    /// `_fileno(stderr)`, which is -2 there), so every log line used to kill the host process with
    /// 0xC000001D -- the SaltyUno crash of 2026-10-04 on the first launch after a migration.
    private func emit(_ level: String, _ message: String) {
        let line = Data("[\(subsystem)] [\(category)] \(level): \(message)\n".utf8)
        try? FileHandle.standardError.write(contentsOf: line)
    }
}
#endif
