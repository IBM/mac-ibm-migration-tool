//
//  ExpandableAppRowView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 21/05/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// Displays an application row that expands to show discovered support files when available.
struct ExpandableAppRowView<Label: View>: View {
    
    // MARK: - Variables
    
    /// The application represented by the row.
    let app: DiscoveredApplication
    /// Tracks which application rows are expanded in the parent view.
    @Binding var expandedAppIDs: Set<UUID>
    /// Optional padding applied around the row content.
    let rowPadding: EdgeInsets
    /// The label shown for the app row.
    @ViewBuilder let label: () -> Label
    
    // MARK: - Initializers
    
    init(app: DiscoveredApplication,
         expandedAppIDs: Binding<Set<UUID>>,
         rowPadding: EdgeInsets = EdgeInsets(),
         @ViewBuilder label: @escaping () -> Label) {
        self.app = app
        self._expandedAppIDs = expandedAppIDs
        self.rowPadding = rowPadding
        self.label = label
    }
    
    // MARK: - Views
    
    var body: some View {
        if AppContext.shouldMigrateAppSupportFiles, let appInfo = app.appInfo, !appInfo.allDiscoveredPaths.isEmpty {
            DisclosureGroup(isExpanded: Binding(
                get: { expandedAppIDs.contains(app.id) },
                set: { isExpanded in
                    if isExpanded {
                        expandedAppIDs.insert(app.id)
                    } else {
                        expandedAppIDs.remove(app.id)
                    }
                }
            )) {
                AppSupportFilesView(appInfo: appInfo)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                label()
            }
            .padding(rowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            label()
                .padding(rowPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
