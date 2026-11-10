//
//  PreferencesMessage.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 29/09/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// Represents a message carrying one preference domain's values for a `PreferenceGroup`.
/// The message body (sent alongside this header) is a binary property list of the domain's values.
struct PreferencesMessage: Codable {

    // MARK: - Variables

    /// The catalog identifier of the `PreferenceGroup` this domain belongs to, e.g. `"dock"`.
    var groupID: String
    /// The `CFPreferences` application ID, e.g. `"com.apple.dock"`. `nil` for the global domain.
    var applicationID: String?
    /// Whether this domain is host-specific (`kCFPreferencesCurrentHost`).
    var isByHost: Bool
}
