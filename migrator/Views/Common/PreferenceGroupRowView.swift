//
//  PreferenceGroupRowView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 01/10/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// Displays a single preference group: its icon, name, number of settings, an info button that
/// reveals exactly what it carries, and an optional selection toggle.
struct PreferenceGroupRowView: View {

    // MARK: - Variables

    /// The preference group represented by this row. Observed directly so the selection toggle
    /// re-renders immediately when `isSelected` changes, rather than relying on an unrelated
    /// SwiftUI update elsewhere to happen to re-evaluate this row.
    @ObservedObject var group: PreferenceGroup
    /// When non-nil, shows a selection toggle bound to this value. When nil, the row is read-only.
    var selection: Binding<Bool>?

    // MARK: - State Variables

    /// Controls the presentation of the "what does this include" info popover.
    @State private var showInfoPopover: Bool = false

    // MARK: - Views

    var body: some View {
        HStack {
            Image(systemName: group.iconName)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .customFont(.body)
                Text(String(format: "migration.preferences.group.settings.count.label".localized, group.settingsCount))
                    .customFont(.footnote)
                    .foregroundColor(.secondary)
            }
            Button(action: {
                showInfoPopover.toggle()
            }, label: {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
            })
            .buttonStyle(.plain)
            .accessibilityLabel(String(format: "accessibility.preferenceGroupRow.infoButton.label".localized, group.name))
            .accessibilityHint("accessibility.preferenceGroupRow.infoButton.hint")
            .popover(isPresented: $showInfoPopover, arrowEdge: .trailing) {
                PreferenceGroupInfoView(group: group)
            }
            Spacer()
            if let selection {
                Toggle(isOn: selection, label: { })
                    .accessibilityLabel(String(format: "accessibility.preferenceGroupRow.toggle.label".localized, group.name))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
