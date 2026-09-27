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

    private func emit(_ level: String, _ message: String) {
        FileHandle.standardError.write(Data("[\(subsystem)] [\(category)] \(level): \(message)\n".utf8))
    }
}
#endif
