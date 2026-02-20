//
//  ServerViewModel.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 26/02/2024.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI
import Combine

/// ViewModel for the Server view.
class ServerViewModel: ObservableObject {
    
    // MARK: - Variables
    
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
    /// Tracks whether the service is registered on the network (indicates Local Network permission status).
    @Published var isServiceRegistered: Bool = false
    /// Tracks whether the listener is running but service is not registered (indicates potential permission issue).
    @Published var showLocalNetworkWarning: Bool = false
    
    // MARK: - Private Variables
    
    /// Collection of cancellable subscriptions to manage memory and avoid retain cycles.
    private var cancellables = Set<AnyCancellable>()
    /// Counts the number of bytes received from file trasfer messages.
    private var bytesReceived: Int = 1
    /// Timer to delay showing the Local Network warning to avoid flashing when service registers successfully.
    private var warningDelayTask: Task<Void, Never>?
    /// Delay in seconds before showing the Local Network warning.
    private let warningDelaySeconds: TimeInterval = 3.0
    
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
                    self.migrationController.stopServer()
                    Utils.Common.preventSleep()
                } else {
                    self.connectionInterrupted = self.connectionEstablished
                }
            }
        }.store(in: &cancellables)
        self.migrationController.$isServiceRegistered.sink { isRegistered in
            Task { @MainActor in
                self.isServiceRegistered = isRegistered
                if isRegistered {
                    // Service registered successfully, cancel any pending warning
                    self.warningDelayTask?.cancel()
                    self.showLocalNetworkWarning = false
                } else if self.migrationController.migrationState == .discovery {
                    // Service not registered, schedule warning after delay
                    self.scheduleWarningDisplay()
                }
            }
        }.store(in: &cancellables)
        self.migrationController.$migrationState.sink { state in
            Task { @MainActor in
                if state == .discovery && !self.isServiceRegistered {
                    // Listener started but service not registered yet, schedule warning
                    self.scheduleWarningDisplay()
                } else {
                    // Not in discovery state, cancel any pending warning
                    self.warningDelayTask?.cancel()
                    self.showLocalNetworkWarning = false
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
    
    /// Schedules the display of the Local Network warning after a delay.
    /// This prevents the warning from flashing briefly when the service registers successfully.
    private func scheduleWarningDisplay() {
        // Cancel any existing delay task
        warningDelayTask?.cancel()
        
        // Schedule new delay task
        warningDelayTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(warningDelaySeconds * 1_000_000_000))
                // After delay, check if we should still show the warning
                if self.migrationController.migrationState == .discovery && !self.isServiceRegistered {
                    self.showLocalNetworkWarning = true
                }
            } catch {
                // Task was cancelled, do nothing
            }
        }
    }
    
    /// Handle the devicePowerStatusChanged notification.
    @objc
    private func devicePowerSourceDidUpdate(_ notification: Notification) {
        guard let newValue = notification.userInfo?["newValue"] as? Bool else { return }
        self.deviceIsConnectedToPower = newValue
    }
}
