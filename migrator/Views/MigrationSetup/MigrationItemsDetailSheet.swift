//
//  MigrationItemsDetailSheet.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 23/01/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// A sheet view that displays the complete list of files and applications
/// included in a migration option, organized in scrollable sections.
struct MigrationItemsDetailSheet: View {
    
    // MARK: - Environment Variables
    
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Variables
    
    /// The migration option containing the items to display
    @ObservedObject var option: MigrationOption
    
    // MARK: - State Variables
    
    /// Tracks expanded application support file rows.
    @State private var expandedAppIDs: Set<UUID> = []
    
    // MARK: - Private Computed Properties
    
    /// Whether there are any files to display
    private var hasFiles: Bool {
        !option.migrationFileList.isEmpty
    }
    
    /// Whether there are any apps to display
    private var hasApps: Bool {
        !option.migrationAppList.isEmpty
    }

    /// Whether there are any preference groups to display
    private var hasPreferences: Bool {
        !option.migrationPreferencesList.isEmpty
    }
    
    // MARK: - Views
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if hasFiles {
                        sectionView(title: "migration.option.detail.files.section",
                                    items: option.migrationFileList)
                    }
                    if hasApps {
                        sectionView(title: "migration.option.detail.apps.section",
                                    apps: option.migrationAppList)
                    }
                    if hasPreferences {
                        sectionView(title: "migration.option.detail.preferences.section",
                                    preferences: option.migrationPreferencesList)
                    }
                    if !hasFiles && !hasApps && !hasPreferences {
                        emptyStateView
                    }
                }
                .padding(20)
            }
            .frame(maxHeight: 500)
        }
        .frame(width: 500)
    }
    
    // MARK: - Subviews
    
    /// Header with title and close button
    private var headerView: some View {
        HStack {
            Text("migration.option.detail.sheet.title")
                .customFont(.title3, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: {
                dismiss()
            }, label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                    .symbolRenderingMode(.hierarchical)
            })
            .buttonStyle(.plain)
            .accessibilityLabel("migration.option.detail.close")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    /// Section view for files
    private func sectionView(title: LocalizedStringKey, items: [MigratorFile]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .customFont(.body, weight: .semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items) { file in
                    MigratorFileView(file: .constant(file), needsDescriptiveLabel: true, showFileSize: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }
        }
    }
    
    /// Section view for apps
    private func sectionView(title: LocalizedStringKey, apps: [DiscoveredApplication]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .customFont(.body, weight: .semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(apps) { app in
                    ExpandableAppRowView(app: app,
                                         expandedAppIDs: $expandedAppIDs,
                                         rowPadding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)) {
                        appRowLabel(app: app)
                    }
                }
            }
        }
    }
    
    /// Section view for preference groups
    private func sectionView(title: LocalizedStringKey, preferences: [PreferenceGroup]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .customFont(.body, weight: .semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(preferences) { group in
                    PreferenceGroupRowView(group: group, selection: nil)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    /// Label content shared by regular and expandable app rows.
    private func appRowLabel(app: DiscoveredApplication) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.relativePath))
                .resizable()
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .customFont(.body)
                    .lineLimit(1)
                if app.architectureType != .unknown {
                    HStack(spacing: 4) {
                        Image(systemName: app.architectureType.iconName)
                            .font(.system(size: 10))
                        Text(app.architectureType.displayName)
                            .customFont(.footnote, weight: .regular)
                    }
                    .foregroundColor(.secondary)
                    .help(Text(app.architectureType.tooltip))
                }
            }
            Spacer()
            if app.totalSize > 0 {
                Text(app.totalSize.fileSizeToFormattedString)
                    .customFont(.footnote, weight: .regular)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
    
    /// Empty state view
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("migration.option.details.empty.list.label")
                .customFont(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Preview

@MainActor
private let previewOption: MigrationOption = {
    let option = MigrationOption(type: .standard(.complete))
    Task {
        await option.loadFiles()
    }
    return option
}()

#Preview {
    MigrationItemsDetailSheet(option: previewOption)
}
