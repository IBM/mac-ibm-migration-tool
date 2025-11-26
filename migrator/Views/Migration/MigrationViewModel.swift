//
//  MigrationViewModel.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 20/02/2024.
//  © Copyright IBM Corp. 2023, 2025
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
    
    /// The migration option used for the migration process.
    private(set) var migrationOption: MigrationOption
    /// Collection of cancellable subscriptions to manage memory and avoid retain cycles.
    private var cancellables = Set<AnyCancellable>()
    /// Variable that store the migration task.
    private var migrationTask: Task<Void, Never>?
    /// Bytes sent to the connected device since the migration started.
    private var bytesSent: Int = 0 {
        didSet {
            Task { @MainActor in
                guard self.migrationProgress != 1 else { return }
                self.migrationProgress = min(Double(self.bytesSent)/Double(self.migrationOption.size), 0.99)
                self.percentageCompleted = "\(min(99, self.bytesSent*100/self.migrationOption.size))%"
            }
        }
    }
    /// Files sent to the connected device since the migration started.
    private var fileSent: Int = 0
    /// Variable used to track when the migration started.
    private var migrationStartTime: Date?
    /// Timer that synchronize the collection of data transfer reports.
    private var dataTransferReportTimer: Timer?
    /// Object used to collect data trasfer reports.
    private var pendingDataTrasferReport: NWConnection.PendingDataTransferReport?
    /// The time interval between one estimate of the time remaining until completion and the next.
    private var dataTrasferTimerInterval: TimeInterval = 5
    
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
    /// Published variable that track the current transfer speed for the data between the devices.
    @Published var trasferSpeed: String = ""
    /// Published variable that track the percentage of completion of the migration.
    @Published var percentageCompleted: String = "migration.page.progressbar.top.percentage.start.label".localized
    
    // MARK: - Initializers
    
    init() {
        deviceIsConnectedToPower = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() != nil
        migrationOption = migrationController.migrationOption ?? MigrationOption(type: .none)
        NotificationCenter.default.addObserver(self, selector: #selector(devicePowerSourceDidUpdate), name: .devicePowerStatusChanged, object: nil)
        migrationController.$connectedDeviceIsReady.sink { isReady in
            if isReady {
                self.startTheMigration()
                MigrationReportController.shared.setMigrationStart()
            }
        }.store(in: &cancellables)
        migrationController.connection?.onBytesSent.sink(receiveValue: { bytesCount in
            Task { @MainActor in
                self.bytesSent += bytesCount
            }
        }).store(in: &cancellables)
        migrationController.connection?.onFileSent.sink(receiveValue: { fileCount in
            Task { @MainActor in
                self.fileSent += fileCount
            }
        }).store(in: &cancellables)
        Task {
            try await migrationController.connection?.sendMigrationSize(migrationOption.size)
        }
    }
    
    // MARK: - Private Methods
    
    // swiftlint:disable function_body_length
    /// Start the migration task.
    private func startTheMigration() {
        self.logger.log("migrationViewModel.startMigration: starting migration", type: .default)
        Task { @MainActor in
            self.bytesSent = self.migrationOption.migrationFileList.reduce(1) { $0 + ($1.sent ? $1.fileSize : 0) }
            self.bytesSent = self.migrationOption.migrationAppList.reduce(self.bytesSent) { $0 + ($1.sent ? $1.fileSize : 0) }
            self.estimatedTimeLeft = String(format: "migration.page.time.estimation.label".localized, "migration.common.calculating.label".localized)
        }
        MigrationReportController.shared.setMigrationSize(Int64(self.migrationOption.size))
        sleep(3)
        pendingDataTrasferReport = migrationController.connection?.connection.startDataTransferReport()
        dataTransferReportTimer = Timer.scheduledTimer(timeInterval: 10, target: self, selector: #selector(estimateTimeLeft), userInfo: nil, repeats: false)
        migrationTask = Task {
            if migrationOption.migrationPreferencesList.isEmpty && !migrationOption.type.migratePreferences {
                do {
                    try await migrationController.connection?.sendDefaults(DefaultsMessage(key: AppContext.skipRebootUserDefaultsKey, boolValue: true))
                } catch {
                    self.logger.log("migrationViewModel.migrationTask: delivery of default value failed with error \"\(error.localizedDescription)\"", type: .error)
                }
            }
            self.migrationStartTime = Date()
            self.logger.log("migrationViewModel.migrationTask: starting migration of files", type: .default)
            for file in migrationOption.migrationFileList {
                guard !file.sent && file.isSelected else { continue }
                do {
                    MLogger.main.log("migrationViewModel.migrationTask: sending file \(file.url.fullURL().relativePath)", type: .default)
                    try await migrationController.connection?.sendFile(file)
                    MLogger.main.log("migrationViewModel.migrationTask: file sent \(file.url.fullURL().relativePath)", type: .default)
                    file.sent = true
                    MigrationReportController.shared.addMigratedFile(file.url.fullURL().relativePath)
                } catch {
                    self.logger.log("migrationViewModel.migrationTask: failed to send file: \(file.url.fullURL().relativePath) - with error: \"\(error.localizedDescription)\"", type: .error)
                    MigrationReportController.shared.addError("migrationViewModel.migrationTask: failed to send file: \(file.url.fullURL().relativePath) - with error: \"\(error.localizedDescription)\"")
                }
            }
            self.logger.log("migrationViewModel.migrationTask: files migration complete", type: .default)
            self.logger.log("migrationViewModel.migrationTask: starting migration of apps", type: .default)
            for app in migrationOption.migrationAppList {
                guard !app.sent && app.isSelected else { continue }
                do {
                    self.logger.log("migrationViewModel.migrationTask: sending app: \(app.url.fullURL().relativePath)", type: .default)
                    try await migrationController.connection?.sendFile(app)
                    self.logger.log("migrationViewModel.migrationTask: app sent: \(app.url.fullURL().relativePath)", type: .default)
                    app.sent = true
                } catch {
                    self.logger.log("migrationViewModel.migrationTask: failed to send file: \(app.url.fullURL().relativePath) - with error: \"\(error.localizedDescription)\"", type: .error)
                    MigrationReportController.shared.addError("migrationViewModel.migrationTask: failed to send file: \(app.url.fullURL().relativePath) - with error: \"\(error.localizedDescription)\"")
                }
            }
            self.logger.log("migrationViewModel.migrationTask: apps migration complete", type: .default)
            do {
                self.pendingDataTrasferReport = nil
                try await migrationController.connection?.sendMigrationCompleted()
                MigrationReportController.shared.setMigrationEnd()
                await MainActor.run {
                    self.percentageCompleted = "100%"
                    self.estimatedTimeLeft = ""
                    self.migrationProgress = 1
                    self.dataTransferReportTimer?.invalidate()
                    self.dataTransferReportTimer = nil
                    NSSound(named: .init("Funk"))?.play()
                    Utils.Window.makeWindowFloating()
                }
            } catch {
                self.logger.log("migrationViewModel.migrationTask: send migration completion failed with error \"\(error.localizedDescription)\"", type: .error)
            }
        }
    }
    // swiftlint:enable function_body_length
    
    @objc
    private func estimateTimeLeft() {
        pendingDataTrasferReport?.collect(queue: .main, completion: { report in
            if let currentReport = report.pathReports.first(where: { self.migrationController.connection?.connection.currentPath?.usesInterfaceType($0.interface.type) ?? false }) {
                let trasferSpeed = Double(currentReport.sentTransportByteCount)/report.duration
                let timeLeftToTrasferBytes = Double(self.migrationOption.size-self.bytesSent)/trasferSpeed
                let rttNeededTime = Double(min(0, self.migrationOption.numberOfFiles-self.fileSent))*currentReport.transportSmoothedRTT
                let totalTimeLeft = timeLeftToTrasferBytes+rttNeededTime
                Task { @MainActor in
                    self.estimatedTimeLeft = String(format: "migration.page.time.estimation.label".localized, totalTimeLeft.prettyFormattedTimeLeft())
                }
            }
            self.pendingDataTrasferReport = self.migrationController.connection?.connection.startDataTransferReport()
            self.dataTransferReportTimer?.invalidate()
            self.dataTransferReportTimer = nil
            self.dataTransferReportTimer = Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(self.estimateTimeLeft), userInfo: nil, repeats: false)
        })
    }
    
    /// Cancel the migration task.
    private func pauseMigration() {
        migrationTask?.cancel()
        migrationStartTime = nil
        dataTransferReportTimer?.invalidate()
        dataTransferReportTimer = nil
    }
    
    /// Handle the devicePowerStatusChanged notification.
    @objc
    private func devicePowerSourceDidUpdate(_ notification: Notification) {
        guard let newValue = notification.userInfo?["newValue"] as? Bool else { return }
        self.deviceIsConnectedToPower = newValue
    }
}
