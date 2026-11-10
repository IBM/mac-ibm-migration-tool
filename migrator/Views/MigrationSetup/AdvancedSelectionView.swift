//
//  AdvancedSelectionView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 15/02/2024.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI
import Combine

/// Struct that define the view representing the advanced selection of files/apps/preferences for the migration.
struct AdavancedSelectionView: View {
    
    // MARK: - Enums
    
    /// Support Enum that define the different sections available.
    enum AdvancedSelectionSection {
        case files
        case applications
        case preferences
        
        /// Title of the section, to be used in the segmented picker.
        var title: String {
            switch self {
            case .files:
                return "migration.option.advanced.segment.files".localized
            case .applications:
                return "migration.option.advanced.segment.applications".localized
            case .preferences:
                return "migration.option.advanced.segment.preferences".localized
            }
        }
    }
    
    // MARK: - Binded Variables
    
    /// Binded list of the available files for this selection.
    @Binding private(set) var migrationOption: MigrationOption
    
    // MARK: - State Variables
    
    /// State variable to track picker selection.
    @State private var advancedSelectionSegment: AdvancedSelectionSection = .files
    /// State variable to track the visibility of hidden files.
    @State private var showHiddenFiles: Bool = false
    /// State variable that counts the number of selected files.
    @State private var selectedFilesNum: Int = 0
    /// State variable that counts the number of selected files.
    @State private var selectedAppsNum: Int = 0
    /// State variable that counts the number of selected preference groups.
    @State private var selectedPreferencesNum: Int = 0
    /// State variable that tracks expanded application support file rows.
    @State private var expandedAppIDs: Set<UUID> = []
    
    // MARK: - Private Variables
    
    /// Collection of cancellable subscriptions to manage memory and avoid retain cycles.
    lazy private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initializers
    
    init(migrationOption: Binding<MigrationOption>) {
        self._migrationOption = migrationOption
    }
    
    // MARK: - Views
    
    var body: some View {
        VStack(spacing: 0) {
            Picker(selection: $advancedSelectionSegment) {
                Text(AdvancedSelectionSection.files.title.localized + (selectedFilesNum > 0 ? " (\(migrationOption.selectedFiles))" : ""))
                    .customFont(.body)
                    .tag(AdvancedSelectionSection.files)
                if !AppContext.shouldExcludeApplicationsFolder {
                    Text(AdvancedSelectionSection.applications.title.localized + (selectedAppsNum > 0 ? " (\(migrationOption.selectedApps))" : ""))
                        .customFont(.body)
                        .tag(AdvancedSelectionSection.applications)
                }
                if AppContext.shouldMigratePreferences && !migrationOption.migrationPreferencesList.isEmpty {
                    Text(AdvancedSelectionSection.preferences.title.localized + (selectedPreferencesNum > 0 ? " (\(migrationOption.selectedPreferences))" : ""))
                        .customFont(.body)
                        .tag(AdvancedSelectionSection.preferences)
                }
            } label: {}
                .pickerStyle(.segmented)
                .background {
                    if #available(macOS 26.0, *) {
                        Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 6))
                    } else {
                        Color("discoveryViewBackground").clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .frame(width: 479, height: 22)
                .padding(.top, -11)
            Spacer()
            switch advancedSelectionSegment {
            case .files:
                HStack {
                    Spacer()
                    if #available(macOS 13.0, *) {
                        Text("migration.setup.page.advanced.select.all")
                            .customFont(.body)
                        Toggle(sources: $migrationOption.migrationFileList, isOn: \.isSelected) { }
                            .padding(.trailing, 16)
                            .accessibilityLabel("migration.setup.page.advanced.select.all")
                    }
                }
                List($migrationOption.migrationFileList) { file in
                    if file.isHidden.wrappedValue && !showHiddenFiles {
                        EmptyView()
                    } else {
                        MigratorFileView(file: file, showFileSize: true, showSelectionToggle: true)
                            .advancedSelectionListRowStyle()
                    }
                }
            case .applications:
                HStack {
                    Spacer()
                    if #available(macOS 13.0, *) {
                        Text("migration.setup.page.advanced.select.all")
                            .customFont(.body)
                        Toggle(sources: $migrationOption.migrationAppList, isOn: \.isSelected) { }
                            .padding(.trailing, 16)
                            .accessibilityLabel("migration.setup.page.advanced.select.all")
                    }
                }
                List($migrationOption.migrationAppList) { $app in
                    if app.migratorFile.isHidden && !showHiddenFiles {
                        EmptyView()
                    } else {
                        ExpandableAppRowView(app: app, expandedAppIDs: $expandedAppIDs) {
                            HStack {
                                MigratorFileView(file: .constant(app.migratorFile), showFileSize: false, showSelectionToggle: false)
                                Spacer()
                                AppTotalSizeView(app: app)
                                architectureBadge(for: app)
                                Toggle(isOn: $app.isSelected) { }
                                    .toggleStyle(.checkbox)
                                    .accessibilityLabel(String(format: "accessibility.advancedSelectionView.appToggle.label".localized, app.name))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .advancedSelectionListRowStyle()
                    }
                }
            case .preferences:
                HStack {
                    Spacer()
                    if #available(macOS 13.0, *) {
                        Text("migration.setup.page.advanced.select.all")
                            .customFont(.body)
                        Toggle(sources: $migrationOption.migrationPreferencesList, isOn: \.isSelected) { }
                            .padding(.trailing, 16)
                            .accessibilityLabel("migration.setup.page.advanced.select.all")
                    }
                }
                List($migrationOption.migrationPreferencesList) { $group in
                    PreferenceGroupRowView(group: group, selection: $group.isSelected)
                        .advancedSelectionListRowStyle()
                }
            }
            if advancedSelectionSegment != .preferences {
                HStack {
                    Toggle(isOn: $showHiddenFiles, label: { })
                        .controlSize(.mini)
                        .toggleStyle(.switch)
                        .accessibilityLabel(String(format: "migration.setup.directory.content.hidden.label".localized, showHiddenFiles ? "migration.setup.directory.content.hidden.label.hide".localized : "migration.setup.directory.content.hidden.label.show".localized))
                    Text(String(format: "migration.setup.directory.content.hidden.label".localized, showHiddenFiles ? "migration.setup.directory.content.hidden.label.hide".localized : "migration.setup.directory.content.hidden.label.show".localized))
                        .customFont(.body)
                    Spacer()
                }
                .padding()
            }
        }
        .padding(.horizontal, 8)
        .onReceive(self.migrationOption.$selectedFiles, perform: { number in
            self.selectedFilesNum = number
        })
        .onReceive(self.migrationOption.$selectedApps, perform: { number in
            self.selectedAppsNum = number
        })
        .onReceive(self.migrationOption.$selectedPreferences, perform: { number in
            self.selectedPreferencesNum = number
        })
    }
    
    // MARK: - Helper Views
    
    /// Creates an architecture badge for a discovered application
    @ViewBuilder
    private func architectureBadge(for app: DiscoveredApplication) -> some View {
        switch app.architectureType {
        case .intelOnly:
            Text("app.architecture.badge.intel".localized)
                .customFont(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.2))
                .foregroundStyle(.primary)
                .cornerRadius(4)
                .help(Text(app.architectureType.tooltip))
        case .universal:
            Text("app.architecture.badge.universal".localized)
                .customFont(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.2))
                .foregroundStyle(.primary)
                .cornerRadius(4)
                .help(Text(app.architectureType.tooltip))
        case .appleSiliconOnly:
            Text("app.architecture.badge.appleSilicon".localized)
                .customFont(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .foregroundStyle(.primary)
                .cornerRadius(4)
                .help(Text(app.architectureType.tooltip))
        case .unknown:
            Text("app.architecture.badge.unknown".localized)
                .customFont(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.2))
                .foregroundStyle(.primary)
                .cornerRadius(4)
                .help(Text(app.architectureType.tooltip))
        }
    }
}

private struct AppTotalSizeView: View {
    @ObservedObject var app: DiscoveredApplication
    @State private var totalSize: Int
    @State private var isSizeAvailable: Bool
    
    init(app: DiscoveredApplication) {
        self.app = app
        self._totalSize = State(initialValue: app.totalSize)
        self._isSizeAvailable = State(initialValue: app.totalSize > 0)
    }
    
    var body: some View {
        Group {
            if isSizeAvailable {
                Text(totalSize.fileSizeToFormattedString)
                    .customFont(.body)
                    .lineLimit(1)
                    .fixedSize()
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                    .padding(.horizontal, 8)
            }
        }
        .onReceive(app.migratorFile.$fileSize) { _ in
            updateSize()
        }
        .onReceive(app.$appInfo) { _ in
            updateSize()
        }
        .onReceive(app.objectWillChange) { _ in
            updateSize()
        }
        .onAppear {
            updateSize()
        }
    }
    
    private func updateSize() {
        totalSize = app.totalSize
        isSizeAvailable = totalSize > 0
    }
}

private extension View {
    /// Applies the shared row styling used by the advanced selection list.
    ///
    /// The modifier expands the row content to the available width, aligns it to the leading edge,
    /// adds bottom spacing, and draws a custom separator. On macOS 13 and later, the system list
    /// row separator is hidden so only the custom separator is visible.
    ///
    /// - Returns: A view configured with the advanced selection list row layout and separator style.
    @ViewBuilder
    func advancedSelectionListRowStyle() -> some View {
        if #available(macOS 13.0, *) {
            self
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 2)
                .listRowSeparator(.hidden)
                .advancedSelectionRowSeparator()
        } else {
            self
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 2)
                .advancedSelectionRowSeparator()
        }
    }
    
    /// Draws a non-interactive separator along the bottom edge of the view.
    ///
    /// - Returns: A view overlaid with a half-point separator using the current AppKit separator color.
    func advancedSelectionRowSeparator() -> some View {
        overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 0.5)
                .allowsHitTesting(false)
        }
    }
}
