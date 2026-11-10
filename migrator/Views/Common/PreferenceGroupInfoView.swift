//
//  PreferenceGroupInfoView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 01/10/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// Popover content showing exactly what settings a `PreferenceGroup` carries: a human-readable
/// summary, and the actual keys and values discovered for it on this Mac.
struct PreferenceGroupInfoView: View {

    // MARK: - Variables

    /// The preference group this popover describes.
    let group: PreferenceGroup

    // MARK: - Private Computed Properties

    /// Domains sorted for stable display order.
    private var sortedDomains: [PreferenceDomain] {
        group.discoveredValues.keys.sorted { ($0.applicationID ?? "") < ($1.applicationID ?? "") }
    }

    // MARK: - Views

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(group.name)
                    .customFont(.title3, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 4) {
                    Text("migration.preferences.info.popover.settings.header")
                        .customFont(.callout, weight: .semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(group.settingDescriptions, id: \.self) { setting in
                        Text("• \(setting)")
                            .customFont(.body)
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: 500, maxHeight: 420)
    }

    // MARK: - Private Methods

    /// Returns a short, human-readable preview of a discovered preference value.
    private func describe(_ value: Any?) -> String {
        switch value {
        case let value as Bool:
            return value ? "true" : "false"
        case let value as NSNumber:
            return value.stringValue
        case let value as String:
            return value
        case let value as [Any]:
            return String(format: "migration.preferences.info.popover.value.array".localized, value.count)
        case let value as [AnyHashable: Any]:
            return String(format: "migration.preferences.info.popover.value.dictionary".localized, value.count)
        case let value as Data:
            return String(format: "migration.preferences.info.popover.value.data".localized, value.count)
        default:
            return "migration.preferences.info.popover.value.unknown".localized
        }
    }
}
