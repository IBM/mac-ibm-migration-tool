//
//  RecapView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 14/10/2025.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

struct RecapView: View {
    
    // MARK: - Environment Variables
    
    @Environment(\.colorScheme) var colorScheme
    
    // MARK: - Constants
    
    /// Closure to execute when an action requires navigation to a different page.
    let action: (MigratorPage) -> Void
    /// The previous page to navigate back to, by default set to the welcome page.
    let previousPage: MigratorPage = .migrationSetup
    /// The next page to navigate forward to, typically the migration setup page.
    let nextPage: MigratorPage = .migration
    
    let includedFiles: [MigratorFile] = MigrationController.shared.migrationOption.migrationFileList.filter { $0.isSelected }
    let includedApps: [MigratorFile] =  MigrationController.shared.migrationOption.migrationAppList.filter { $0.isSelected }
    
    // MARK: - State Variables
    
    /// Controls whether the alert warning users about preventing device sleep during migration is presented.
    @State private var showDeviceSleepAlert: Bool = false
    /// Controls whether the alert informing users about potential file interaction during migration is presented.
    @State private var showFileInteractionAlert: Bool = false
    /// Indicates whether hidden files and applications should be shown in the recap lists.
    @State private var showHiddenFiles: Bool = false
    
    // MARK: - Observable Variables
    
    /// Observable view model object to handle data and logic for the migration setup
    @ObservedObject var viewModel: RecapViewModel = RecapViewModel()
    
    // MARK: - Views
    
    var body: some View {
        VStack {
            CustomizableIconView(pageIdentifier: "recap")
                .padding(.top, 55)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            Text("recap.page.title")
                .multilineTextAlignment(.center)
                .font(.system(size: 27, weight: .bold))
                .padding(.bottom)
            if viewModel.isLoading {
                Spacer()
                ProgressView()
                    .task {
                        await viewModel.prepareRecapData()
                    }
                Spacer()
            } else {
                fileSection
                duplicateWarningBar
            }
            Spacer()
            Divider()
            actionButtons
                .padding(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
        }
        .overlay {
            if viewModel.connectionInterrupted {
                CustomAlertView(title: "connection.error.alert.title".localized, message: "connection.error.alert.restoring.message".localized) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.regular)
                }
            }
        }
        .alert("migration.devicesleep.alert.title", isPresented: $showDeviceSleepAlert) {
            Button("migration.devicesleep.alert.main.action.label") {
                Task { @MainActor in
                    showFileInteractionAlert.toggle()
                }
            }
            .accessibilityHint("accessibility.recapView.deviceSleepAlert.mainButton.hint")
        } message: {
            Text("migration.devicesleep.alert.message")
        }
        .alert("migration.fileinteraction.alert.title", isPresented: $showFileInteractionAlert) {
            Button("migration.fileinteraction.alert.main.action.label") {
                Task { @MainActor in
                    action(nextPage)
                }
            }
            .accessibilityHint("accessibility.recapView.fileInteractionAlert.mainButton.hint")
        } message: {
            Text("migration.fileinteraction.alert.message")
        }
    }
    
    var willMigrateSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("recap.page.will.be.migrated.title")
                    .font(.headline)
                    .padding(.bottom, 4)
                ForEach(includedFiles) { item in
                    if item.isHidden && !showHiddenFiles {
                        EmptyView()
                    } else {
                        MigratorFileView(file: .constant(item), needsDescriptiveLabel: true, showFileSize: false, showPartialItemInfo: true)
                            .padding(.leading, 4)
                    }
                }
                ForEach(includedApps) { item in
                    if item.isHidden && !showHiddenFiles {
                        EmptyView()
                    } else {
                        MigratorFileView(file: .constant(item), needsDescriptiveLabel: true, showFileSize: false)
                            .padding(.leading, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .layoutPriority(1)
            .padding()
        }
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color("discoveryViewBackground"))
        }
    }
    
    var excludedSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("recap.page.wont.be.migrated.title")
                    .font(.headline)
                    .padding(.bottom, 4)
                ForEach(viewModel.itemsExcluded) { item in
                    if item.isHidden && !showHiddenFiles {
                        EmptyView()
                    } else {
                        MigratorFileView(file: .constant(item), needsDescriptiveLabel: true, showFileSize: false, showPartialItemInfo: true)
                        .padding(.leading, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .layoutPriority(1)
            .padding()
        }
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color("discoveryViewBackground"))
        }
    }
    
    var duplicateWarningBar: some View {
        HStack(alignment: .center) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(viewModel.duplicateFileMessage)
            Spacer()
        }
        .padding()
        .frame(width: 550)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color("discoveryViewBackground"))
        }
    }
    
    var actionButtons: some View {
        HStack {
            Spacer()
            Button(action: { didPressSecondaryButton() }, label: {
                Text("recap.page.secondary.button.label").padding(4)
            })
            .accessibilityHint("accessibility.recapView.secondaryButton.hint")
            Button(action: { didPressMainButton() }, label: {
                Text("recap.page.main.button.label").padding(4)
            })
            .disabled(viewModel.isLoading)
            .padding(.leading, 6)
            .keyboardShortcut(.defaultAction)
            .accessibilityHint("accessibility.recapView.mainButton.hint")
        }
    }
    
    var fileSection: some View {
        Group {
            HStack {
                Toggle(isOn: $showHiddenFiles, label: { })
                    .controlSize(.mini)
                    .toggleStyle(.switch)
                Text(String(format: "migration.setup.directory.content.hidden.label".localized, showHiddenFiles ? "migration.setup.directory.content.hidden.label.hide".localized : "migration.setup.directory.content.hidden.label.show".localized))
                Spacer()
            }
            HStack(spacing: 10) {
                if !MigrationController.shared.migrationOption.migrationFileList.isEmpty
                    || !MigrationController.shared.migrationOption.migrationAppList.isEmpty
                    || !MigrationController.shared.migrationOption.migrationPreferencesList.isEmpty {
                    willMigrateSection
                }
                if !viewModel.itemsExcluded.isEmpty {
                    excludedSection
                }
            }
        }
        .frame(width: 550)
    }
    
    // MARK: - Private Methods
    
    private func didPressMainButton() {
        showDeviceSleepAlert.toggle()
    }
    
    private func didPressSecondaryButton() {
        action(previousPage)
    }
}

#Preview {
    RecapView(action: { _ in })
}
