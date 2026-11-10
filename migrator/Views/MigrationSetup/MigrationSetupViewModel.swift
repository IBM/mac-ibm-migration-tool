//
//  MigrationSetupViewModel.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 29/01/2024.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import SwiftUI
import Combine

/// ViewModel for the MigrationSetup view.
@MainActor
final class MigrationSetupViewModel: ObservableObject {
    
    // MARK: - Enums
    
    /// Defines the possible states of the MigrationSetup view.
    enum MigrationSetupViewState {
        case loadingMetadata        // State when the view is loading metadata.
        case standardSelection      // State for standard migration option selection.
        case advancedSelection      // State for advanced migration option selection.
    }
    
    // MARK: - Observable Variables
    
    /// Observable object that controls the migration process.
    let migrationController: MigrationController
    
    // MARK: - Published Variables
    
    /// Current state of the view, driving the UI.
    @Published var viewState: MigrationSetupViewState {
        didSet {
            updateButtonLabel()
        }
    }
    /// List of available migration options.
    @Published var pickerMigrationOptions: [MigrationOption]
    /// Advanced migration option.
    @Published var advancedMigrationOption: MigrationOption!
    /// Currently selected migration option by the user.
    @Published var chosenOption: MigrationOption {
        didSet {
            updateButtonLabel()
            self.isReadyForMigration = self.chosenOption.readyForMigration
            MigrationReportController.shared.setMigrationChosenOption(self.chosenOption.type.identifier)
        }
    }
    /// Display string for available space on the destination, starts with a placeholder.
    @Published var availableSpaceOnDestinationLabel: String = ""
    /// Tracks if the chosen migration option is ready for the migration.
    @Published var isReadyForMigration: Bool = false
    /// Tracks if the chosen migration option size has been calculated.
    @Published var isSizeCalculationFinal: Bool = false
    /// Tracks if the connection have been interrupted
    @Published var connectionInterrupted: Bool = false
    
    // MARK: - Private Variables
    
    /// Stores any cancellable instances to manage memory and prevent leaks.
    private var cancellables = Set<AnyCancellable>()
    /// Store the value of available space on destination.
    private var availableSpaceOnDestination: Int = -1 {
        didSet {
            updateButtonLabel()
        }
    }
    /// Minimum required available space in bytes (20GB)
    private let minimumRequiredSpace: Int = 20 * 1024 * 1024 * 1024
    
    // MARK: - Initializers
    
    /// Initializes the ViewModel with default values and sets up a subscription for available space changes.
    init(_ migrationController: MigrationController) {
        self.migrationController = migrationController
        self.viewState = .loadingMetadata
        self.pickerMigrationOptions = []
        self.chosenOption = MigrationOption(type: .none)
        
        // Subscribe to the `onAvailableSpaceChange` event of `migrationController` to update the available space.
        self.migrationController.connection?.onAvailableSpaceChange.sink(receiveValue: { [weak self] value in
            self?.availableSpaceOnDestination = value
        }).store(in: &cancellables)
        self.migrationController.$isConnected.sink { [weak self] newValue in
            self?.connectionInterrupted = !newValue
        }.store(in: &cancellables)
        
        Utils.Common.preventSleep()
    }

    // MARK: - Public Methods
    
    /// Loads metadata for each migration option asynchronously and updates the view state.
    func loadMigrationOptions() async {
        if let availableSpace = self.migrationController.connection?.connectedDeviceAvailableSpace {
            self.availableSpaceOnDestination = availableSpace
        }
        let migrationTypes: [MigrationOption.MigrationOptionType] = AppContext.migrationPresets.map { .standard($0) } + [.advanced]
        for migrationType in migrationTypes {
            let option = MigrationOption(type: migrationType)
            await option.loadFiles()
            if AppContext.shouldMigratePreferences {
                await option.discoverPreferences()
            }
            option.$size.sink { size in
                guard self.chosenOption.type == migrationType else { return }
                self.updateButtonLabel(with: size)
            }.store(in: &cancellables)
            option.$readyForMigration.sink { [weak self] isReady in
                guard let self, self.chosenOption.type == migrationType else { return }
                self.isReadyForMigration = isReady
            }.store(in: &cancellables)
            option.$isFinalSize.sink { [weak self] isFinal in
                guard isFinal else { return }
                Task { @MainActor in
                    self?.evaluateSizeCalculationResult()
                }
            }.store(in: &cancellables)
            switch migrationType {
            case .standard:
                self.pickerMigrationOptions.append(option)
            case .advanced:
                self.advancedMigrationOption = option
            case .none:
                break
            }
        }
        self.viewState = .standardSelection

        if AppContext.shouldMigrateAppSupportFiles {
            await discoverAppSupportFiles()
        }
        await loadMigrationOptionsSizes()
    }

    /// Discovers app support files once per unique app and shares the result across all migration options.
    ///
    /// Complete and Advanced each build their own `DiscoveredApplication` instances for the same apps
    /// (so selection and `sent` state stay independent), but the discovered `AppInfo` is
    /// selection-independent, so it's computed once and shared. Sharing the instance also shares
    /// `AppInfo.cachedTotalSize`, so support-file sizing runs once too.
    private func discoverAppSupportFiles() async {
        MLogger.main.log("migrationSetupViewModel.discoverAppSupportFiles: starting app support file discovery")

        let allOptions = pickerMigrationOptions + [advancedMigrationOption].compactMap { $0 }
        var appsByURL: [URL: [DiscoveredApplication]] = [:]
        var orderedURLs: [URL] = []
        for option in allOptions {
            for app in option.migrationAppList {
                let key = app.url.standardizedFileURL
                if appsByURL[key] == nil {
                    orderedURLs.append(key)
                }
                appsByURL[key, default: []].append(app)
            }
        }

        let discovery = AppPathDiscovery()
        for url in orderedURLs {
            guard let apps = appsByURL[url], let representative = apps.first else { continue }
            let appInfo = await discovery.discoverPaths(forAppNamed: representative.name, at: representative.url, sensitivity: .enhanced)
            apps.forEach { $0.appInfo = appInfo }
        }

        MLogger.main.log("migrationSetupViewModel.discoverAppSupportFiles: completed app support file discovery for \(orderedURLs.count) unique app(s)")
    }

    /// Reset the migration options and view state.
    func resetMigration() {
        self.advancedMigrationOption = nil
        self.pickerMigrationOptions = []
        self.chosenOption = MigrationOption(type: .none)
        self.viewState = .loadingMetadata
        self.availableSpaceOnDestinationLabel = ""
        self.isReadyForMigration = false
        self.isSizeCalculationFinal = false
        self.connectionInterrupted = false
        self.availableSpaceOnDestination = -1
    }
    
    /// Checks if available space data has been received from the destination device
    func hasAvailableSpaceData() -> Bool {
        return availableSpaceOnDestination != -1
    }
    
    /// Checks if the available space after migration would be below the minimum required (10GB)
    func hasInsufficientSpace() -> Bool {
        guard availableSpaceOnDestination != -1 else { return false }
        let remainingSpace = availableSpaceOnDestination - chosenOption.size
        return remainingSpace < minimumRequiredSpace
    }
    
    // MARK: - Private Methods
    
    /// Update the bottom label of the setup view with the correct text based on the view state and on the selected option.
    private func updateButtonLabel(with size: Int? = nil) {
        let migrationSize = size ?? chosenOption.size
        if self.availableSpaceOnDestination == -1 {
            self.availableSpaceOnDestinationLabel = String(format: "migration.setup.page.bottom.info.size.label".localized, "migration.common.calculating.label".localized)
        } else {
            self.availableSpaceOnDestinationLabel = String(format: "migration.setup.page.bottom.info.size.label".localized,
                                                           (self.availableSpaceOnDestination - migrationSize).fileSizeToFormattedString)
        }
    }
    
    /// Async method that calculate the size of the migration options based on the files they contain.
    private func loadMigrationOptionsSizes() async {
        for migrationOption in pickerMigrationOptions {
            await migrationOption.detectAppArchitectures()
            await migrationOption.fetchFilesSizeAndCount()
        }
        await advancedMigrationOption.detectAppArchitectures()
        await advancedMigrationOption.fetchFilesSizeAndCount()
    }

    /// Check if all the migration options have completed size calculation.
    private func evaluateSizeCalculationResult() {
        guard !self.pickerMigrationOptions.isEmpty && self.advancedMigrationOption != nil else { return }
        guard self.pickerMigrationOptions.allSatisfy({ $0.isFinalSize }) && self.advancedMigrationOption.isFinalSize else { return }
        self.isSizeCalculationFinal = true
    }
}
