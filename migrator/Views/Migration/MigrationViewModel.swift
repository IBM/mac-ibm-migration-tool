//
//  MigrationViewModel.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 20/02/2024.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Combine
import SwiftUI
import IOKit.ps
import Network

/// ViewModel for the Migration view.
class MigrationViewModel: ObservableObject {
    
    // MARK: - Variables
    
    /// Shared instance of the migration controller.
    var migrationController: MigrationController = MigrationController.shared
    
    var usedInterface: String {
        guard let currentInterfaceType = self.migrationController.connection?.currentInterfaceType else { return "" }
        switch currentInterfaceType {
        case .wifi, .cellular:
            return " " + "migration.page.technology.wifi.label".localized
        case .wiredEthernet:
            return " " + "migration.page.technology.thunderbolt.label".localized
        default:
            return ""
        }
    }
            
    // MARK: - Private Variables
    
    /// Collection of cancellable subscriptions to manage memory and avoid retain cycles.
    private var cancellables = Set<AnyCancellable>()
    /// Flag indicating whether a migration has already been initiated.
    private var isMigrationRunning: Bool = false
    
    // MARK: - Private Constants
    
    /// Logger instance.
    private let logger: MLogger = MLogger.main
        
    // MARK: - Published Variables
    
    /// Published variable that track if the device is connected to a power source.
    @Published var deviceIsConnectedToPower: Bool = true
    /// Published variable that track the migration process.
    @Published var migrationProgress: Double = 0
    /// Published variable that track the estimated time lef for the migration.
    @Published var estimatedTimeLeft: String = ""
    /// Published variable that track the percentage of completion of the migration.
    @Published var percentageCompleted: String = "migration.page.progressbar.top.percentage.start.label".localized
    /// Tracks if the connection have been interrupted
    @Published var connectionInterrupted: Bool = false
    
    // MARK: - Initializers
    
    init() {
        deviceIsConnectedToPower = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() != nil
        NotificationCenter.default.addObserver(self, selector: #selector(devicePowerSourceDidUpdate), name: .devicePowerStatusChanged, object: nil)
        
        // Subscribe to MigrationController's published properties
        migrationController.$estimatedTimeLeft.sink { [weak self] timeLeft in
            Task { @MainActor in
                self?.estimatedTimeLeft = timeLeft
            }
        }.store(in: &cancellables)
        
        migrationController.$percentageCompleted.sink { [weak self] percentage in
            Task { @MainActor in
                self?.percentageCompleted = percentage
            }
        }.store(in: &cancellables)
        
        migrationController.$migrationProgress.sink { [weak self] progress in
            Task { @MainActor in
                self?.migrationProgress = progress
            }
        }.store(in: &cancellables)
        self.migrationController.$isConnected.sink { newValue in
            Task { @MainActor in
                self.connectionInterrupted = !newValue
            }
        }.store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    func startMigration() {
        guard !isMigrationRunning else { return }
        isMigrationRunning = true
        MigrationReportController.shared.setMigrationStart()
        Task { @MainActor in
            self.migrationController.startMigration()
        }
    }
    
    // MARK: - Private Methods
    
    /// Handle the devicePowerStatusChanged notification.
    @objc
    private func devicePowerSourceDidUpdate(_ notification: Notification) {
        guard let newValue = notification.userInfo?["newValue"] as? Bool else { return }
        self.deviceIsConnectedToPower = newValue
    }
}
