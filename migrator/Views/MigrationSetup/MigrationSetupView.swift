//
//  MigrationSetupView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 17/01/2024.
//  © Copyright IBM Corp. 2023, 2026
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
    let nextPage: MigratorPage = AppContext.shouldSkipMigrationSummary ? .migration : .recap
    
    // MARK: - Observable Variables
    
    /// Observable view model object to handle data and logic for the migration setup
    @ObservedObject var viewModel: MigrationSetupViewModel = MigrationController.shared.migrationSetupViewModel
    
    // MARK: - State Variables
    
    @State private var showDeviceSleepAlert: Bool = false
    @State private var showFileInteractionAlert: Bool = false
    @State private var showIntelAppConfirmation: Bool = false
    @State private var isLoading: Bool = false
    @State private var showInsufficientSpacePopover: Bool = false
    
    // MARK: - Views
    
    var body: some View {
        VStack {
            CustomizableIconView(pageIdentifier: "setup")
                .padding(.top, 55)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            Text("migration.setup.page.title")
                .multilineTextAlignment(.center)
                .customFont(size: 27, weight: .bold)
                .padding(.bottom, 8)
            if $viewModel.viewState.wrappedValue != MigrationSetupViewModel.MigrationSetupViewState.advancedSelection {
                Text("migration.setup.page.subtitle")
                    .multilineTextAlignment(.center)
                    .customFont(.body)
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
                        // Only load if not already loaded
                        if self.viewModel.pickerMigrationOptions.isEmpty {
                            await self.viewModel.loadMigrationOptions()
                        } else {
                            await MainActor.run {
                                self.viewModel.viewState = .standardSelection
                            }
                        }
                    }
            case .standardSelection, .advancedSelection:
                selectionView
                    .padding(.horizontal, viewModel.viewState == .advancedSelection ? 130 : 160)
                    .padding(.bottom, 15)
            }
            Spacer()
            Divider()
            HStack {
                bottomLabelView
                Spacer()
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .padding(.leading, 6)
                } else {
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
                    .disabled(!(viewModel.isSizeCalculationFinal && viewModel.isReadyForMigration) || (viewModel.hasInsufficientSpace() && viewModel.hasAvailableSpaceData()))
                    .padding(.leading, 6)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint("accessibility.migrationSetupView.mainButton.hint")
                }
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
                .customFont(.body)
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
                .customFont(.body)
        }
        .sheet(isPresented: $showIntelAppConfirmation) {
            IncompatibleAppConfirmationView(incompatibleApps: MigrationController.shared.intelOnlyAppsForConfirmation,
                                            destinationArchitecture: MigrationController.shared.destinationDeviceArchitecture ?? .appleSilicon,
                                            onConfirm: didTapIncompatibleAppConfirmationProceedButton,
                                            onReview: didTapIncompatibleAppConfirmationReviewButton,
                                            onIgnore: didTapIncompatibleAppConfirmationIgnoreButton)
        }
    }
    
    private var bottomLabelView: some View {
        HStack {
            if viewModel.viewState == .loadingMetadata || !viewModel.isSizeCalculationFinal {
                Text("migration.setup.page.bottom.info.loading.label")
                    .customFont(.body)
                    .padding(.trailing, 8)
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .accessibilityHidden(true)
            } else if viewModel.hasAvailableSpaceData() {
                if viewModel.hasInsufficientSpace() {
                    Button {
                        showInsufficientSpacePopover.toggle()
                    } label: {
                        Image(systemName: "exclamationmark")
                            .foregroundColor(.red)
                            .font(.title2)
                            .padding(4)
                    }
                    .clipShape(Circle())
                    .accessibilityHint("accessibility.migrationView.warningButton.hint")
                    .popover(isPresented: $showInsufficientSpacePopover, arrowEdge: .bottom) {
                        Text("migration.setup.page.bottom.info.storage.help")
                            .customFont(.body)
                            .padding()
                    }
                }
                Text(viewModel.availableSpaceOnDestinationLabel)
                    .customFont(.body)
                    .foregroundColor(viewModel.hasInsufficientSpace() ? .red : nil)
            } else {
                Button {
                    showInsufficientSpacePopover.toggle()
                } label: {
                    Image(systemName: "exclamationmark")
                        .foregroundColor(.orange)
                        .font(.title2)
                        .padding(4)
                }
                .clipShape(Circle())
                .accessibilityHint("accessibility.migrationView.warningButton.hint")
                .popover(isPresented: $showInsufficientSpacePopover, arrowEdge: .bottom) {
                    Text("migration.setup.page.bottom.noinfo.size.label")
                        .customFont(.body)
                        .padding()
                        .frame(maxWidth: 500)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    private var selectionView: some View {
        ZStack {
            Color("discoveryViewBackground")
                .clipShape(RoundedRectangle(cornerRadius: viewModel.viewState == .advancedSelection ? 12 : 20))
                .shadow(color: Color(red: 0, green: 0, blue: 0, opacity: 0.15), radius: 6, x: 0, y: 0)
                .accessibilityHidden(true)
            if viewModel.viewState == .advancedSelection {
                AdavancedSelectionView(migrationOption: $viewModel.chosenOption)
                    .transition(.opacity)
            } else {
                VStack(alignment: .leading) {
                    Picker("", selection: $viewModel.chosenOption) {
                        ForEach($viewModel.pickerMigrationOptions) { element in
                            VStack {
                                MigrationOptionView(option: element.wrappedValue)
                                    .padding(.trailing, 31)
                                Divider()
                                    .padding(.leading, -38)
                                    .padding(.trailing, -7)
                            }
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
                                .customFont(.body)
                        })
                        .buttonStyle(.link)
                        .accessibilityHint("accessibility.migrationSetupView.advancedSelectionButton.hint")
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                .transition(.opacity)
            }
        }
        .mask(
            RoundedRectangle(cornerRadius: viewModel.viewState == .advancedSelection ? 12 : 20)
                .padding(.top, viewModel.viewState == .advancedSelection ? -11 : 0)
        )
    }
    
    private var mainButtonLabel: some View {
        Text("migration.setup.page.main.button.label")
            .customFont(.body)
            .padding(4)
    }
    
    private var secondaryButtonLabel: some View {
        Text("migration.setup.page.button.secondary.label")
            .customFont(.body)
            .padding(4)
    }
    
    // MARK: - Private Methods
    
    private func didPressMainButton() {
        MigrationController.shared.migrationOption = viewModel.chosenOption
        if !MigrationController.shared.validateAppSelection() {
            showIntelAppConfirmation = true
            return
        }
        if AppContext.shouldSkipMigrationSummary {
            showDeviceSleepAlert.toggle()
        } else {
            action(nextPage)
        }
    }
    
    private func didPressSecondaryButton() {
        withAnimation(.bouncy) {
            $viewModel.viewState.wrappedValue = .standardSelection
            $viewModel.chosenOption.wrappedValue = MigrationOption(type: .none)
            $viewModel.isReadyForMigration.wrappedValue = false
        }
    }
    
    private func didTapIncompatibleAppConfirmationReviewButton() {
        MigrationController.shared.resetIntelAppMigration()
    }
    
    private func didTapIncompatibleAppConfirmationProceedButton() {
        if AppContext.shouldSkipMigrationSummary {
            showDeviceSleepAlert = true
        } else {
            action(nextPage)
        }
    }
    
    private func didTapIncompatibleAppConfirmationIgnoreButton() {
        Task { @MainActor in
            self.isLoading = true
        }
        MigrationController.shared.removeIncompatibleApps { success in
            if success {
                if AppContext.shouldSkipMigrationSummary {
                    showDeviceSleepAlert = true
                } else {
                    action(nextPage)
                }
            } else {
                MigrationController.shared.resetIntelAppMigration()
                Task { @MainActor in
                    self.isLoading = false
                }
            }
        }
    }
}

#Preview {
    MigrationSetupView(action: { _ in })
        .frame(width: 812, height: 600)
}
