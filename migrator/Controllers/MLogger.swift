//
//  MLogger.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 21/03/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import os.log

/// Object who handle the logging process for the app.
final class MLogger {
    
    enum LogLevel: String {
        case noLog
        case standard
        case debug
    }
    
    // MARK: - Static Variables
    
    /// Shared instance of MLogger.
    static let main: MLogger = MLogger()
    
    // MARK: - Private Variables
    
    /// System logger.
    private var logger: Logger
    /// Level of verbosity for the logs.
    private var logLevel: LogLevel
    
    private var logFileHandle: FileHandle?
    
    // MARK: - Intializers
    
    private init() {
        self.logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Migration")
        self.logLevel = AppContext.loggingLevel
        if let logFileURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Logs").appendingPathComponent("\(Bundle.main.name).log") {
            if !FileManager.default.fileExists(atPath: logFileURL.relativePath) {
                FileManager.default.createFile(atPath: logFileURL.relativePath, contents: nil)
            }
            self.logFileHandle = try? FileHandle(forWritingTo: logFileURL)
            _ = try? logFileHandle?.seekToEnd()
        }
    }
    
    deinit {
        try? logFileHandle?.close()
    }
    
    // MARK: Public Methods
    
    /// Log the given message usign the given log level.
    /// - Parameters:
    ///   - message: the log message.
    ///   - type: the log level.
    func log(_ message: String, type: OSLogType = .debug) {
        switch logLevel {
        case .noLog:
            break
        case .standard:
            switch type {
            case .error, .fault, .default:
                logger.log(level: type, "\(message)")
                write(message, type: type)
            default:
                logger.log(level: type, "\(message)")
            }
        case .debug:
            logger.log(level: type, "\(message)")
            write(message, type: type)
        }
    }
    
    // MARK: - Private Methods
    
    /// Write the logs to the log file located in ~/Library/Logs/
    private func write(_ message: String, type: OSLogType) {
        if let data = "[\(Date().formatted(date: .abbreviated, time: .complete))] \(type.humanReadableValue.capitalized): \(message)\n".data(using: .utf8) {
            try? logFileHandle?.write(contentsOf: data)
        }
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
