//
//  ServerViewModel.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 26/02/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI
import Combine

/// ViewModel for the Server view.
class ServerViewModel: ObservableObject {
    
    // MARK: - Variables
    
    var usedInterface: String {
        guard let currentPath = self.migrationController.connection?.connection.currentPath else { return "" }
        guard let currentInterface = currentPath.availableInterfaces.first(where: { currentPath.usesInterfaceType($0.type) }) else { return "" }
        switch currentInterface.type {
        case .wifi, .cellular:
            return " " + "migration.page.technology.wifi.label".localized
        case .wiredEthernet:
            return " " + "migration.page.technology.thunderbolt.label".localized
        default:
            return ""
        }
    }
    
    // MARK: - Observed Variables
    
    /// Observable object to control and observe migration status
    @ObservedObject private var migrationController: MigrationController = MigrationController.shared
    
    // MARK: - Published Variables
    
    /// Published variable that track if the device is connected to a power source.
    @Published var deviceIsConnectedToPower: Bool = true
    /// Indicates whether a connection to a migration client has been established.
    @Published var connectionEstablished: Bool = false
    /// Tracks unexpected connection interruptions.
    @Published var connectionInterrupted: Bool = false
    /// Track the progress of the migration.
    @Published var migrationProgress: Double = 0
    /// Published variable that track the percentage of completion of the migration.
    @Published var percentageCompleted: String = "server.page.progressbar.top.percentage.start.label".localized
    /// Random pairing code.
    @Published var randomCode: String = ""
    
    // MARK: - Private Variables
    
    /// Collection of cancellable subscriptions to manage memory and avoid retain cycles.
    private var cancellables = Set<AnyCancellable>()
    /// Counts the number of bytes received from file trasfer messages.
    private var bytesReceived: Int = 1
    
    // MARK: - Initializers
    
    init() {
        self.deviceIsConnectedToPower = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() != nil
        self.randomCode = Utils.Common.generateRandomCode(digits: 6)
        self.migrationController.startServer(withPasscode: randomCode)
        self.migrationController.$isConnected.sink { newValue in
            Task { @MainActor in
                if newValue {
                    self.connectionEstablished = newValue
                    self.connectionInterrupted = false
                    // Stops the server to prevent additional connections once one is established.
                    self.migrationController.stopServer()
                    Utils.Common.preventSleep()
                } else {
                    self.connectionInterrupted = self.connectionEstablished
                }
            }
        }.store(in: &cancellables)
        self.migrationController.$bytesReceived.sink { bytesCount in
            Task { @MainActor in
                self.bytesReceived = bytesCount
                 if self.migrationController.sizeOfMigration != 0 {
                    self.migrationProgress = min(Double(self.bytesReceived)/Double(self.migrationController.sizeOfMigration), 0.99)
                    self.percentageCompleted = "\(min(99, self.bytesReceived*100/self.migrationController.sizeOfMigration))%"
                }
            }
        }.store(in: &cancellables)
        self.migrationController.$isMigrationCompleted.sink { isCompleted in
            guard isCompleted else { return }
            Task { @MainActor in
                self.percentageCompleted = "100%"
                self.migrationProgress = 1
                self.cancellables.removeAll()
                Utils.Window.makeWindowFloating()
            }
        }.store(in: &cancellables)
        NotificationCenter.default.addObserver(self, selector: #selector(devicePowerSourceDidUpdate), name: .devicePowerStatusChanged, object: nil)
    }
    
    func resetMigration() {
        self.migrationController.resetMigration()
    }
    
    // MARK: - Private Functions
    
    /// Handle the devicePowerStatusChanged notification.
    @objc
    private func devicePowerSourceDidUpdate(_ notification: Notification) {
        guard let newValue = notification.userInfo?["newValue"] as? Bool else { return }
        self.deviceIsConnectedToPower = newValue
    }
}
