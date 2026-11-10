//
//  MLogger.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 21/03/2024.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import os.log
import Synchronization

/// Object who handle the logging process for the app.
final class MLogger: Sendable {

    enum LogLevel: String, Sendable {
        case noLog
        case standard
        case debug
    }

    /// Logical area of the app a log line belongs to. Maps to a distinct `os.Logger` category
    /// so Console.app filtering works per-component, while everything still lands in the same log file.
    enum Category: String, Sendable {
        case general = "General"
        case migration = "Migration"
        case network = "Network"
        case pairing = "Pairing"
        case discovery = "Discovery"
        case report = "Report"
        case device = "Device"
    }

    // MARK: - Static Variables

    /// Shared instance of MLogger.
    static let main: MLogger = MLogger()

    // MARK: - Private Variables

    /// Mutable logger state, guarded by `state` so `MLogger` can be shared across threads.
    private struct State {
        /// System loggers, one per `Category`, created lazily on first use.
        var loggers: [Category: Logger] = [:]
        var logFileHandle: FileHandle?
    }

    /// Level of verbosity for the logs.
    private let logLevel: LogLevel
    /// Also serializes writes to the log file.
    private let state: Mutex<State>

    // MARK: - Intializers

    private init() {
        self.logLevel = AppContext.loggingLevel
        var initialState = State()
        // In DEBUG, suffix the filename with the process ID: two instances of the app are
        // routinely run on the same Mac for pairing/migration testing (a server and a browser
        // side), and without this they'd both open the same path with no coordination between
        // their independent `FileHandle`s, tearing each other's writes (seen in practice: lines
        // from one process overwriting bytes mid-line of the other's).
#if DEBUG
        let logFileName = "\(Bundle.main.name)-\(ProcessInfo.processInfo.processIdentifier).log"
#else
        let logFileName = "\(Bundle.main.name).log"
#endif
        if let logFileURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Logs").appendingPathComponent(logFileName) {
            if !FileManager.default.fileExists(atPath: logFileURL.relativePath) {
                FileManager.default.createFile(atPath: logFileURL.relativePath, contents: nil)
            }
            initialState.logFileHandle = try? FileHandle(forWritingTo: logFileURL)
            _ = try? initialState.logFileHandle?.seekToEnd()
        }
        self.state = Mutex(initialState)
    }

    deinit {
        state.withLock { try? $0.logFileHandle?.close() }
    }

    // MARK: Public Methods

    /// Returns a lightweight proxy that always logs under the given `category`,
    /// so call sites don't need to repeat it on every call.
    func scoped(to category: Category) -> ScopedLogger {
        ScopedLogger(logger: self, category: category)
    }

    /// Log the given message usign the given log level.
    /// - Parameters:
    ///   - message: the log message.
    ///   - type: the log level.
    ///   - category: the logical area of the app this message belongs to.
    func log(_ message: String, type: OSLogType = .debug, category: Category = .general) {
        let logger = logger(for: category)
        switch logLevel {
        case .noLog:
            switch type {
            case .error, .fault:
                logger.log(level: type, "\(message)")
            default:
                break
            }
        case .standard:
            switch type {
            case .error, .fault, .default:
                logger.log(level: type, "\(message)")
                write(message, type: type, category: category)
            default:
                break
            }
        case .debug:
            logger.log(level: type, "\(message)")
            write(message, type: type, category: category)
        }
    }

    // MARK: - Private Methods

    /// Returns the cached `Logger` for the given category, creating it on first use.
    private func logger(for category: Category) -> Logger {
        state.withLock { state in
            if let existing = state.loggers[category] {
                return existing
            }
            let created = Logger(subsystem: Bundle.main.bundleIdentifier!, category: category.rawValue)
            state.loggers[category] = created
            return created
        }
    }

    /// Write the logs to the log file located in ~/Library/Logs/
    private func write(_ message: String, type: OSLogType, category: Category) {
        if let data = "[\(Date().formatted(date: .abbreviated, time: .complete))] \(type.humanReadableValue.capitalized) [\(category.rawValue)]: \(message)\n".data(using: .utf8) {
            state.withLock { state in
                try? state.logFileHandle?.write(contentsOf: data)
            }
        }
    }
}

/// Forwards every call to the owning `MLogger` with a fixed `Category`, so a type that only
/// ever logs under one category (e.g. `MigrationController` → `.migration`) can declare
/// `let logger = MLogger.main.scoped(to: .migration)` and call `logger.log(...)` as before.
struct ScopedLogger: Sendable {
    fileprivate let logger: MLogger
    fileprivate let category: MLogger.Category

    func log(_ message: String, type: OSLogType = .debug) {
        logger.log(message, type: type, category: category)
    }
}

extension OSLogType {
    /// Human readable value for the different OSLogType(s).
    var humanReadableValue: String {
        switch self {
        case .debug:
            return "debug"
        case .info:
            return "info"
        case .default:
            return "info"
        case .error:
            return "error"
        case .fault:
            return "fault"
        default:
            return "info"
        }
    }
}
