//
//  AdvancedSelectionView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 15/02/2024.
//  © Copyright IBM Corp. 2023, 2025
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
                    .tag(AdvancedSelectionSection.files)
                Text(AdvancedSelectionSection.applications.title.localized + (selectedAppsNum > 0 ? " (\(migrationOption.selectedApps))" : ""))
                    .tag(AdvancedSelectionSection.applications)
            } label: {}
                .pickerStyle(.segmented)
                .background {
                    Color("discoveryViewBackground").clipShape(RoundedRectangle(cornerRadius: 6))
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
                        Toggle(sources: $migrationOption.migrationFileList, isOn: \.isSelected) { }
                            .padding(.trailing, 16)
                    }
                }
                List($migrationOption.migrationFileList) { file in
                    if file.isHidden.wrappedValue && !showHiddenFiles {
                        EmptyView()
                    } else {
                        HStack {
                            MigratorFileView(file: file, showFileSize: true, showSelectionToggle: true)
                        }
                    }
                }
            case .applications:
                HStack {
                    Spacer()
                    if #available(macOS 13.0, *) {
                        Text("migration.setup.page.advanced.select.all")
                        Toggle(sources: $migrationOption.migrationAppList, isOn: \.isSelected) { }
                            .padding(.trailing, 16)
                    }
                }
                List($migrationOption.migrationAppList) { file in
                    if file.isHidden.wrappedValue && !showHiddenFiles {
                        EmptyView()
                    } else {
                        HStack {
                            MigratorFileView(file: file, showFileSize: true, showSelectionToggle: true)
                        }
                    }
                }
            case .preferences:
                EmptyView()
            }
            HStack {
                Toggle(isOn: $showHiddenFiles, label: { })
                    .controlSize(.mini)
                    .toggleStyle(.switch)
                Text(String(format: "migration.setup.directory.content.hidden.label".localized, showHiddenFiles ? "migration.setup.directory.content.hidden.label.hide".localized : "migration.setup.directory.content.hidden.label.show".localized))
                Spacer()
            }
            .padding()
        }
        .padding(.horizontal, 8)
        .onReceive(self.migrationOption.$selectedFiles, perform: { number in
            self.selectedFilesNum = number
        })
        .onReceive(self.migrationOption.$selectedApps, perform: { number in
            self.selectedAppsNum = number
        })
    }
}

private let ASVPreviewOption = MigrationOption(type: .advanced)
#Preview {
    AdavancedSelectionView(migrationOption: .constant(ASVPreviewOption))
        .frame(width: 812, height: 600)
        .task {
            await ASVPreviewOption.loadFiles()
        }
}
