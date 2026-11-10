//
//  PreferenceGroup.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 01/10/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import Combine

/// Represents one selectable item in the Preferences migration category (e.g. "Dock Preferences"),
/// backed by the values discovered for it on this Mac.
@MainActor
final class PreferenceGroup: ObservableObject {

    // MARK: - Published Variables

    /// Whether this group is selected for migration.
    @Published var isSelected: Bool = false

    // MARK: - Variables

    /// The catalog definition this group was built from.
    nonisolated let catalogItem: PreferenceCatalogItem
    /// Serialized binary plist payload discovered on this Mac for each domain, already filtered
    /// to the keys this group cares about. Stored pre-serialized (rather than `[String: Any]`,
    /// which isn't `Sendable`) because discovery happens on a background task.
    let discoveredValues: [PreferenceDomain: Data]
    /// True once this group has been sent to the connected device.
    var sent: Bool = false

    /// Stable identifier matching the catalog item, used for logging and the migration report.
    nonisolated var catalogID: String { catalogItem.id }
    /// Localized display name, e.g. "Dock Preferences".
    var name: String { catalogItem.nameKey.localized }
    /// SF Symbol shown next to the group.
    var iconName: String { catalogItem.iconName }
    /// Localized, human-readable list of the settings this group carries, shown in its info popover.
    var settingDescriptions: [String] { catalogItem.settingDescriptionKeys.map { $0.localized } }
    /// Number of settings this group carries, shown next to its name.
    var settingsCount: Int { settingDescriptions.count }
    /// Estimated size in bytes of the serialized payload that will be sent for this group.
    var payloadSize: Int {
        discoveredValues.values.reduce(0) { $0 + $1.count }
    }

    // MARK: - Initializers

    /// Initialize a new preference group from a catalog item and the values discovered for it on this Mac.
    /// - Parameters:
    ///   - catalogItem: The catalog definition this group represents.
    ///   - discoveredValues: The serialized, filtered payload found for each of the catalog item's domains.
    init(catalogItem: PreferenceCatalogItem, discoveredValues: [PreferenceDomain: Data]) {
        self.catalogItem = catalogItem
        self.discoveredValues = discoveredValues
    }
}

// MARK: - Identifiable, Equatable, Hashable Conformance

extension PreferenceGroup: Identifiable, Equatable, Hashable {
    nonisolated var id: String { catalogID }

    nonisolated static func == (lhs: PreferenceGroup, rhs: PreferenceGroup) -> Bool {
        return lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
