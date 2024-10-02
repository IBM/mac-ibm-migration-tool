//
//  SymbolicLinkMessage.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 30/01/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// Represents a message that describes a symbolic link for the migration process.
struct SymbolicLinkMessage: Codable {
    
    // MARK: - Variables
    
    /// The source location of the symbolic link, encapsulated in a `MigratorFileURL` to include any necessary metadata or formatting.
    var source: MigratorFileURL
    /// The absolute destination path of the symbolic link, also encapsulated in a `MigratorFileURL`.
    /// This is used when the relative path is not applicable or when an absolute path is necessary for clarity or functionality.
    var absoluteDestination: MigratorFileURL
    /// An optional relative destination path for the symbolic link. This can be used in lieu of the absolute path
    /// when the destination is relative to a specific directory or when preserving the relative structure is important.
    var relativeDestination: String?
}
