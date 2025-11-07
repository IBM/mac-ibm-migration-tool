//
//  MigrationItem.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 17/10/2025.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// Represents an item that will be migrated or excluded from migration
struct MigrationItem: Identifiable, Hashable {
    /// Unique identifier for the item
    let id = UUID()
    
    /// Name of the item (file, folder, or application)
    let name: String
    
    /// Description of the item
    let description: String
}
