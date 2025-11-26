//
//  MigrationSetupViewModel.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 29/01/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import SwiftUI
import Combine

/// ViewModel for the MigrationSetup view.
class MigrationSetupViewModel: ObservableObject {
    
    // MARK: - Enums
    
    /// Defines the possible states of the MigrationSetup view.
    enum MigrationSetupViewState {
        case loadingMetadata        // State when the view is loading metadata.
        case standardSelection      // State for standard migration option selection.
        case advancedSelection      // State for advanced migration option selection.
    }
    
    // MARK: - Observable Variables
    
    /// Observable object that controls the migration process.
    @ObservedObject var migrationController: MigrationController
    
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
            Task { @MainActor in
                self.isReadyForMigration = self.chosenOption.readyForMigration
            }
            MigrationReportController.shared.setMigrationChosenOption(self.chosenOption.type.rawValue)
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
        self.migrationController.$isConnected.sink { newValue in
            Task { @MainActor in
                self.connectionInterrupted = !newValue
            }
        }.store(in: &cancellables)
        
        Utils.Common.preventSleep()
    }
    
    // MARK: - Public Methods
    
    /// Loads metadata for each migration option asynchronously and updates the view state.
    func loadMigrationOptions() async {
        if let availableSpace = self.migrationController.connection?.connectedDeviceAvailableSpace {
            self.availableSpaceOnDestination = availableSpace
        }
        for migrationType in MigrationOption.MigrationOptionType.allCases {
            guard migrationType != .none else { continue }
            let option = MigrationOption(type: migrationType)
            await option.loadFiles()
            option.$size.sink { size in
                guard self.chosenOption.type == migrationType else { return }
                self.updateButtonLabel(with: size)
            }.store(in: &cancellables)
            option.$readyForMigration.sink { isReady in
                guard self.chosenOption.type == migrationType else { return }
                Task { @MainActor in
                    self.isReadyForMigration = isReady
                }
            }.store(in: &cancellables)
            option.$isFinalSize.sink { isFinal in
                guard isFinal else { return }
                Task {
                    self.evaluateSizeCalculationResult()
                }
            }.store(in: &cancellables)
            switch migrationType {
            case .lite, .complete:
                self.pickerMigrationOptions.append(option)
            case .advanced:
                self.advancedMigrationOption = option
            case .none:
                break
            }
        }
        await MainActor.run {
            self.viewState = .standardSelection
        }
        await loadMigrationOptionsSizes()
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
    
    // MARK: - Private Methods
    
    /// Update the bottom label of the setup view with the correct text based on the view state and on the selected option.
    @MainActor
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
            await migrationOption.fetchFilesSizeAndCount()
        }
        await advancedMigrationOption.fetchFilesSizeAndCount()
    }
    
    /// Check if all the migration options have completed size calculation.
    @MainActor
    private func evaluateSizeCalculationResult() {
        guard !self.pickerMigrationOptions.isEmpty && self.advancedMigrationOption != nil else { return }
        guard self.pickerMigrationOptions.allSatisfy({ $0.isFinalSize }) && self.advancedMigrationOption.isFinalSize else { return }
        self.isSizeCalculationFinal = true
    }
}
