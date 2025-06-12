//
//  MigrationSetupView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 17/01/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// Struct representing the Migration Setup view.
struct MigrationSetupView: View {
    
    // MARK: - Environment Variables
    
    @Environment(\.colorScheme) var colorScheme

    // MARK: - Constants
    
    /// Closure to execute when an action requires navigation to a different page.
    let action: (MigratorPage) -> Void
    /// The previous page to navigate back to, by default set to the welcome page.
    let previousPage: MigratorPage = .browser
    /// The next page to navigate forward to, typically the migration setup page.
    let nextPage: MigratorPage = .migration

    // MARK: - Observable Variables
    
    /// Observable view model object to handle data and logic for the migration setup
    @ObservedObject var viewModel: MigrationSetupViewModel = MigrationSetupViewModel()
    
    // MARK: - State Variables
    
    @State private var showDeviceSleepAlert: Bool = false
    @State private var showFileInteractionAlert: Bool = false
    
    // MARK: - Views
    
    var body: some View {
        VStack {
            Image("icon")
                .resizable()
                .frame(width: 86, height: 86)
                .padding(.top, 55)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            Text("migration.setup.page.title")
                .multilineTextAlignment(.center)
                .font(.system(size: 27, weight: .bold))
                .padding(.bottom, 8)
            if $viewModel.viewState.wrappedValue != MigrationSetupViewModel.MigrationSetupViewState.advancedSelection {
                Text("migration.setup.page.subtitle")
                    .multilineTextAlignment(.center)
                    .padding(.bottom)
                    .padding(.horizontal, 40)
            }
            Spacer()
            switch viewModel.viewState {
            case .loadingMetadata:
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.large)
                    .task(priority: .high) {
                        await self.viewModel.loadMigrationOptions()
                    }
            case .standardSelection, .advancedSelection:
                selectionView
                    .padding(.horizontal, viewModel.viewState == .advancedSelection ? 130 : 180)
                    .padding(.bottom, viewModel.viewState == .advancedSelection ? 15 : 25)
            }
            Spacer()
            Divider()
            HStack {
                bottomLabelView
                Spacer()
                Button(action: {
                    didPressSecondaryButton()
                }, label: {
                    secondaryButtonLabel
                })
                .hiddenConditionally(isHidden: viewModel.viewState != .advancedSelection)
                .accessibilityHint("accessibility.migrationSetupView.secondaryButton.hint")
                Button(action: {
                    didPressMainButton()
                }, label: {
                    mainButtonLabel
                })
                .disabled(!(viewModel.isSizeCalculationFinal && viewModel.isReadyForMigration))
                .padding(.leading, 6)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("accessibility.migrationSetupView.mainButton.hint")
            }
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
            .accessibilityHint("accessibility.migrationSetupView.devicSleepAlert.mainButton.hint")
        } message: {
            Text("migration.devicesleep.alert.message")
        }
        .alert("migration.fileinteraction.alert.title", isPresented: $showFileInteractionAlert) {
            Button("migration.fileinteraction.alert.main.action.label") {
                Task { @MainActor in
                    MigrationController.shared.migrationOption = viewModel.chosenOption
                    action(nextPage)
                }
            }
            .accessibilityHint("accessibility.migrationSetupView.fileInteractionAlert.mainButton.hint")
        } message: {
            Text("migration.fileinteraction.alert.message")
        }
    }
    
    private var bottomLabelView: some View {
        HStack {
            if viewModel.viewState == .loadingMetadata || !viewModel.isSizeCalculationFinal {
                Text("migration.setup.page.bottom.info.loading.label")
                    .padding(.trailing, 8)
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .accessibilityHidden(true)
            } else {
                Text(viewModel.availableSpaceOnDestinationLabel)
            }
        }
    }
    
    private var selectionView: some View {
        ZStack {
            Color("discoveryViewBackground")
                .clipShape(RoundedRectangle(cornerRadius: viewModel.viewState == .advancedSelection ? 6 : 20))
                .shadow(color: Color(red: 0, green: 0, blue: 0, opacity: 0.15), radius: 6, x: 0, y: 0)
                .accessibilityHidden(true)
            if viewModel.viewState == .advancedSelection {
                AdavancedSelectionView(migrationOption: $viewModel.chosenOption)
            } else {
                VStack(alignment: .leading) {
                    Picker("", selection: $viewModel.chosenOption) {
                        ForEach($viewModel.pickerMigrationOptions) { element in
                            MigrationOptionView(option: element.wrappedValue)
                                .tag(element.wrappedValue)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .controlSize(.large)
                    .labelsHidden()
                    .padding(.leading, 16)
                    .padding(.trailing, 8)
                    .padding(.top, 8)
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation(.bouncy) {
                                $viewModel.chosenOption.wrappedValue = viewModel.advancedMigrationOption
                                $viewModel.viewState.wrappedValue = .advancedSelection
                            }
                        }, label: {
                            Text("migration.setup.page.advanced.setup.button.label")
                        })
                        .buttonStyle(.link)
                        .accessibilityHint("accessibility.migrationSetupView.advancedSelectionButton.hint")
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
        }
    }
    
    private var mainButtonLabel: some View {
        Text("migration.setup.page.main.button.label")
            .padding(4)
    }
    
    private var secondaryButtonLabel: some View {
        Text("migration.setup.page.button.secondary.label")
            .padding(4)
    }

    // MARK: - Private Methods
    
    private func didPressMainButton() {
        showDeviceSleepAlert.toggle()
    }
    
    private func didPressSecondaryButton() {
        withAnimation(.bouncy) {
            $viewModel.viewState.wrappedValue = .standardSelection
            $viewModel.chosenOption.wrappedValue = MigrationOption(type: .none)
            $viewModel.isReadyForMigration.wrappedValue = false
        }
    }
}

#Preview {
    MigrationSetupView(action: { _ in })
    .frame(width: 812, height: 600)
}
