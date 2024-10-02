//
//  MigratorError.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 12/01/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// A tracked error.
enum MigratorError {
    // Enum cases for different types of errors that can occur during migration
    case fileError(type: Enums.FileError)
    case connectionError(type: Enums.ConnectionError)
    case internalError(type: Enums.InternalError)

    // Nested enum namespace for file and connection errors
    class Enums { }
}

/// Conforming to the `LocalizedError` protocol to provide localized descriptions for errors
extension MigratorError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .fileError(let type):
            return type.localizedDescription
        case .connectionError(let type):
            return type.localizedDescription
        case .internalError(let type):
            return type.localizedDescription
        }
    }
}

// MARK: - Model Errors

/// Extension to `MigratorError.Enums` for file errors.
extension MigratorError.Enums {
    /// Enum cases for different types of file errors.
    enum FileError {
        case noData
        case noInfo
        case failedDuringFileHandling(error: Error? = nil)
        case failedToWriteFile
    }
    /// Enum cases for different types of connection errors.
    enum ConnectionError {
        case failedToSendFile
    }
    /// Enum case for different types of app's internal errors.
    enum InternalError {
        case undefined
        case casting
        case data
    }
}

/// Conforming to the `LocalizedError` protocol to provide localized descriptions for file errors
extension MigratorError.Enums.FileError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noData:
            return "MigratorError FileError noData"
        case .noInfo:
            return "MigratorError FileError noInfo"
        case .failedDuringFileHandling:
            return "MigratorError FileError failedDuringFileHandling"
        case .failedToWriteFile:
            return "MigratorError FileError failedToWriteFile"
        }
    }
}

/// Conforming to the `LocalizedError` protocol to provide localized descriptions for connection errors
extension MigratorError.Enums.ConnectionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .failedToSendFile:
            return "MigratorError ConnectionError failed to send file"
        }
    }
}

/// Conforming to the `LocalizedError` protocol to provide localized descriptions for internal errors
extension MigratorError.Enums.InternalError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .undefined:
            return "MigratorError InternalError undefined error"
        case .casting:
            return "MigratorError InternalError casting error"
        case .data:
            return "MigratorError InternalError data error"
        }
    }
}
