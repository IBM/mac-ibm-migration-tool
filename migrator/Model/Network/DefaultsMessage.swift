//
//  DefaultsMessage.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 05/09/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// Represents a message that describes a UserDefaults value.
struct DefaultsMessage: Codable {
    
    // MARK: - Variables

    /// UserDefaults key.
    var key: String
    /// The boolean value if the app needs to trasfer a boolean default setting.
    var boolValue: Bool?
    /// The string value if the app needs to trasfer a string default setting.
    var stringValue: String?
}
