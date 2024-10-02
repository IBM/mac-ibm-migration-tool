//
//  DuplicateFilesHandlingPolicy.swift
//  migrator
//
//  Created by Simone Martorelli on 29/09/2024.
//  © Copyright IBM Corp. 2023, 2024
//

/// The possible method to handle duplicate files on the destination device.
enum DuplicateFilesHandlingPolicy: String, Codable {
    case ignore /// Ignore the new file received and keep the one present on the destination device.
    case overwrite /// Overwrite the file available on the destination device with the new one.
    case move /// Move the old file available on the destination device to a backup folder on the desktop.
}
