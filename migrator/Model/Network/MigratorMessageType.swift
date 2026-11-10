//
//  MigratorMessageType.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 30/01/2024.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// Defines the types of messages that can be sent and received in the migration process.
enum MigratorMessageType: UInt32 {
    case hostname = 0       // Represents a message containing the hostname of a device.
    case file = 1           // Represents a message containing a file, typically used for transferring a single file.
    case multipartFile = 2  // Represents a part of a file, used in scenarios where large files are split into multiple parts for transfer.
    case availableSpace = 3 // Represents a message containing information about the available storage space on a device.
    case result = 4         // Represents a message that contains the result of a requested operation, such as the success or failure of a file transfer.
    case invalid = 5        // Represents an invalid or unrecognized message type, typically used for error handling.
    case symlink = 6        // Represents a message containing a symbolic link, including its source and target paths.
    case directory = 7      // Represents a message indicating a directory, possibly used when initiating the transfer of a directory's contents.
    case metadata = 8       // Represents a metadata message.
    case defaults = 9       // Represents a message with UserDefaults values.
    case deviceInfo = 10    // Represents a message containing device information including architecture.
    case authHello = 11     // Client -> server: first PAKE message, carries the client's share.
    case authResponse = 12  // Server -> client: carries the server's share and confirmation MAC.
    case authConfirm = 13   // Client -> server: carries the client's confirmation MAC.
    case authResult = 14    // Server -> client: final accept/reject of the pairing exchange.
    case pairingRequest = 15  // Client -> server: pre-auth, carries the client's hostname only.
    case pairingDecision = 16 // Server -> client: the destination human's accept/decline of pairingRequest.
    case pairingCancelled = 17 // Client -> server: the source human aborted before pairing completed.
    case preferences = 18   // Represents a message containing a macOS preferences domain's values.
    case migrationPaused = 19 // Source -> destination: the source human paused the migration and is about to disconnect.
}
