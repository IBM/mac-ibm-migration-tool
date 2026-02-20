//
//  MigrationController.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 01/02/2024.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import Network
import Combine
import AppKit

// swiftlint:disable type_body_length file_length
/// Controls the migration process, managing network connections, and handling data transfer.
class MigrationController: ObservableObject {
    
    // MARK: - Enum Definitions
    
    enum MigrationState {
        case initial
        case discovery
        case fetching
        case wrongOTPCodeSent
        case connectionEstablished
        case readyForMigration
        case fileMigration
        case appMigration
        case preferencesMigration
        case interrupted
        case cancelled
        case paused
        case restoringConnection
        case completing
        case completed
    }
    
    enum OperatingMode {
        case server
        case browser
    }
    
    // MARK: - Static Constants
    
    /// Singleton instance for global access.
    static let shared: MigrationController = MigrationController()
    
    // MARK: - Variables
    
    /// Holds the current network connection. Observes changes to dynamically handle new connections.
    var connection: NetworkConnection? {
        didSet {
            self.setupSubscriptions()
        }
    }
    /// Responsible for browsing the network for available services.
    var browser: NetworkBrowser
    /// Acts as the server to accept incoming network connections.
    var server: NetworkServer
    /// The chosen option for the migration.
    var migrationOption: MigrationOption!
    /// The selected result in the device list.
    var selectedBrowserResult: NWBrowser.Result!
    /// Define if the current instance is used as `server` or `browser`
    var operatingMode: OperatingMode!
    /// Persistent view model for migration setup to avoid reloading options
    lazy var migrationSetupViewModel: MigrationSetupViewModel = MigrationSetupViewModel(self)

    // MARK: - Private Variables
    
    /// Collection of cancellable subscriptions to manage memory and avoid retain cycles.
    private var cancellables = Set<AnyCancellable>()
    /// Passcode used to secure the connection.
    private var passcode: String!
    /// Tracks the selected destination endpoint.
    private var destinationDevice: NWBrowser.Result!
    /// Tracks connection states.
    private var connectionState: NWConnection.State = .setup
    /// Tracks the number of connection restoration attempts
    private var connectionRestorationAttempts: Int = 0
    /// Maximum number of connection restoration attempts before giving up
    private let maxConnectionRestorationAttempts: Int = 10
    /// Timer that synchronize the collection of data transfer reports.
    private var dataTransferReportTimer: Timer?
    /// Object used to collect data trasfer reports.
    private var pendingDataTrasferReport: NWConnection.PendingDataTransferReport?
    /// The time interval between one estimate of the time remaining until completion and the next.
    private var dataTrasferTimerInterval: TimeInterval = 5
    /// Variable used to track when the migration started.
    private var migrationStartTime: Date?
    /// Bytes sent to the connected device since the migration started.
    private var bytesSent: Int = 0 {
        didSet {
            Task { @MainActor in
                guard let migrationOption = self.migrationOption else { return }
                guard self.migrationProgress != 1 else { return }
                self.migrationProgress = min(Double(self.bytesSent)/Double(migrationOption.size), 0.99)
                self.percentageCompleted = "\(min(99, self.bytesSent*100/migrationOption.size))%"
            }
        }
    }
    /// Files sent to the connected device since the migration started.
    private var filesSent: Int = 0
    /// Variable that store the migration task.
    private var migrationTask: Task<Void, Never>?
    
    // MARK: - Private Constants
    
    /// Logger instance.
    private let logger: MLogger = MLogger.main
    /// Flag to indicate if migration is paused due to resource constraints
    private var isPausedForResources: Bool = false
    /// Semaphore to limit concurrent file operations
    private let fileOperationSemaphore = AsyncSemaphore(value: 5)
    /// Semaphore to limit concurrent file operations
    private let connectionOperationSemaphore = AsyncSemaphore(value: 5)
    
    // MARK: - Published Variables
    
    /// Logs errors encountered during the migration process.
    @Published var errorLog: String = ""
    /// Indicates whether a connection to a migration client or server has been established.
    @Published var isConnected: Bool = false
    /// Stores the hostname of the connected device, defaulting to "Unknown" when not connected.
    @Published var hostName: String = "Unknown"
    /// Keeps track of discovered network devices during the browsing process.
    @Published var browserResults: [NetworkDevice] = []
    /// Represents the progress of the migration process as a value between 0 and 1.
    @Published var migrationProgress: Double = 0
    /// Notify if the connected device is ready to receive data.
    @Published var connectedDeviceIsReady: Bool = false
    /// The size of the migration received from the source device.
    @Published var sizeOfMigration: Int = 0
    /// Tracks the number of bytes received from file trasfer messages.
    @Published var bytesReceived: Int = 0
    /// Tracks the completion of the migration.
    @Published var isMigrationCompleted: Bool = false
    /// Tracks migration controller state.
    @Published var migrationState: MigrationState = .initial {
        didSet {
            logger.log("migrationController.migrationState: State changed from \(oldValue) to \(migrationState)", type: .default)
        }
    }
    /// Published variable that track the estimated time left for the migration.
    @Published var estimatedTimeLeft: String = ""
    /// Published variable that track the current transfer speed for the data between the devices.
    @Published var transferSpeed: String = ""
    /// Published variable that track the percentage of completion of the migration.
    @Published var percentageCompleted: String = "migration.page.progressbar.top.percentage.start.label".localized
    /// Tracks whether the service is successfully registered on the network (indicates Local Network permission status).
    @Published var isServiceRegistered: Bool = false
    /// Stores the architecture of the destination device
    @Published var destinationDeviceArchitecture: AppArchitecture?
    /// Stores the full device info of the destination device
    @Published var destinationDeviceInfo: DeviceInfoMessage?
    /// Indicates whether Intel app confirmation dialog should be shown
    @Published var shouldShowIntelAppWarning: Bool = false
    /// Stores Intel-only apps that need user confirmation
    @Published var intelOnlyAppsForConfirmation: [DiscoveredApplication] = []
            
    // MARK: - Initializers
    
    private init() {
        self.server = NetworkServer()
        self.browser = NetworkBrowser()
        
        // Sets up a sink to handle new connections to the server.
        self.server.onNewConnection.sink { [weak self] newConnection in
            self?.logger.log("migrationController.onNewConnection: new connection requeste received from \"\(newConnection.debugDescription)\"", type: .default)
            // Prevents connecting to the same endpoint more than once.
            if let currentConnection = self?.connection?.connection, currentConnection.endpoint == newConnection.endpoint {
                newConnection.cancel()
            } else {
                // Establishes a new connection if the device is different.
                self?.connection = NetworkConnection(connection: newConnection)
            }
        }.store(in: &cancellables)
        
        // Monitors the state of the listener on the server to log changes and adjust the connection status.
        self.server.onNewListenerState.sink { [weak self] newState in
            self?.logger.log("migrationController.networkServer.stateUpdateHandler: new state \"\(newState)\"", type: .default)
            switch newState {
            case .failed, .cancelled:
                self?.isConnected = self?.connection != nil
            default:
                break
            }
        }.store(in: &cancellables)
        
        // Monitors service registration changes to detect Local Network permission issues.
        self.server.onServiceRegistrationUpdate.sink { [weak self] change in
            self?.logger.log("migrationController.networkServer.serviceRegistrationUpdate: service registration change \"\(change)\"", type: .default)
            Task { @MainActor in
                switch change {
                case .add:
                    self?.isServiceRegistered = true
                case .remove:
                    self?.isServiceRegistered = false
                @unknown default:
                    break
                }
            }
        }.store(in: &cancellables)
        
        self.browser.onNewBrowserState.sink { [weak self] newState in
            self?.logger.log("migrationController.networkBrowser.stateUpdateHandler: new state \"\(newState)\"", type: .default)
        }.store(in: &cancellables)
        
        // Handles changes in browser results to update the list of discovered network devices.
        self.browser.onNewBrowserResults.sink { [weak self] changes in
            self?.logger.log("migrationController.networkBrowser.onNewBrowserResults: new state \"\(changes.debugDescription)\"", type: .default)
            guard !changes.isEmpty else { return }
            for change in changes {
                switch change {
                case .added(let result):
                    self?.browserResults.append(NetworkDevice(browserResult: result))
                case .removed(let result):
                    self?.browserResults.removeAll(where: { $0.browserResult == result })
                case .changed(old: let old, new: let new, _):
                    self?.browserResults.removeAll(where: { $0.browserResult == old })
                    self?.browserResults.append(NetworkDevice(browserResult: new))
                default:
                    continue
                }
            }
        }.store(in: &cancellables)
    }
    
    /// Starts the network server to accept incoming connections with a given passcode.
    @MainActor
    func startServer(withPasscode passcode: String) {
        self.operatingMode = .server
        self.passcode = passcode
        logger.log("migrationController.networkServer.start: starting server...", type: .default)
        do {
            try server.start(withPasscode: passcode)
            migrationState = .discovery
        } catch let error {
            logger.log("migrationController.networkServer.start: failed to start the server with error \"\(error.localizedDescription)\"", type: .error)
            self.errorLog = error.localizedDescription
        }
    }
    
    /// Stops the network server, ending the ability to accept new connections.
    @MainActor
    func stopServer() {
        logger.log("migrationController.networkServer.stop: stopping the server...", type: .default)
        server.stop()
        isServiceRegistered = false
        migrationState = .initial
    }
    
    /// Starts the network browser to search for available network services.
    @MainActor
    func startBrowser() {
        self.operatingMode = .browser
        logger.log("migrationController.networkBrowser.start: starting browser...", type: .default)
        browser.start()
        migrationState = .discovery
    }
    
    /// Stops the network browser, ending the search for network services.
    @MainActor
    func stopBrowser() {
        logger.log("migrationController.networkBrowser.stop: stopping the  browser...", type: .default)
        browser.stop()
        migrationState =  migrationState == .restoringConnection ? .restoringConnection : .initial
        browserResults = []
    }
    
    /// Attempts to connect to a specified device using a passcode. Calls the completion handler with the result.
    @MainActor
    func connect(to device: NWBrowser.Result, withPasscode passcode: String = "000000") {
        self.passcode = passcode
        self.destinationDevice = device
        logger.log("migrationController.connect: starting connection with device \"\(device)\"", type: .default)
        guard !self.isConnected else {
            logger.log("migrationController.connect: a connection has already been established \"\(self.connection?.connection.debugDescription ?? "nil")\", discarding new connection request...", type: .default)
            return
        }

        // Stops browsing to focus on establishing the connection.
        self.stopBrowser()
        
        // Clean up old connection before creating a new one
        if let oldConnection = self.connection {
            logger.log("migrationController.connect: cleaning up old connection before creating new one", type: .default)
            oldConnection.connection.forceCancel()
            // Don't set connection to nil - we'll reuse the wrapper object
        }
        
        // Creates a new connection to the selected device or reuses existing wrapper
        if self.connection == nil {
            self.connection = NetworkConnection(endpoint: device.endpoint, withPasscode: passcode)
            self.connection?.connection.start(queue: .main)
        } else {
            // Reuse existing NetworkConnection wrapper but restore the underlying connection
            self.connection = NetworkConnection(endpoint: device.endpoint, withPasscode: passcode)
            self.connection?.connection.start(queue: .main)
        }
        
        logger.log("migrationController.connect: starting connection...", type: .default)
        self.hostName = device.resultName
        MigrationReportController.shared.setTargetDevice(device.resultName)
        self.checkConnectionEstablishment(5)
    }
    
    @MainActor
    func resetMigration() {
        stopServer()
        stopBrowser()
        connection?.connection.forceCancel()
        connection = nil
        migrationOption = nil
        migrationProgress = 0
        sizeOfMigration = 0
        browserResults = []
        selectedBrowserResult = nil
        isPausedForResources = false
        connectionRestorationAttempts = 0
        migrationSetupViewModel.resetMigration()
    }
    
    @MainActor
    func restoreConnection() {
        logger.log("migrationController.restoreConnection: attempting to restore connection", type: .default)
        
        switch self.operatingMode {
        case .server:
            // For server mode, restart the server to accept new connections
            logger.log("migrationController.restoreConnection: restarting server", type: .default)
            self.startServer(withPasscode: self.passcode)
        case .browser:
            // For browser mode, restore the existing connection object instead of creating a new one
            if let existingConnection = self.connection {
                logger.log("migrationController.restoreConnection: restoring existing connection object", type: .default)
                if existingConnection.restoreConnection() {
                    logger.log("migrationController.restoreConnection: connection restoration initiated", type: .default)
                    self.checkConnectionEstablishment(5)
                } else {
                    logger.log("migrationController.restoreConnection: connection restoration failed, falling back to new connection", type: .error)
                    self.connect(to: self.destinationDevice, withPasscode: self.passcode)
                }
            } else {
                logger.log("migrationController.restoreConnection: no existing connection, creating new one", type: .default)
                self.connect(to: self.destinationDevice, withPasscode: self.passcode)
            }
        case .none:
            logger.log("migrationController.restoreConnection: no operating mode set", type: .error)
        }
    }
    
    // MARK: - Private Methods
    
    /// Sets up Combine subscriptions for all relevant `NetworkConnection` publishers to keep the
    /// `MigrationController` state synchronized with the underlying connection lifecycle and data flow.
    private func setupSubscriptions() {
        connection?.onHostNameChange.sink(receiveValue: { hostName in
            Task { @MainActor in
                self.hostName = hostName
                self.migrationState = .readyForMigration
                MigrationReportController.shared.setTargetDevice(hostName)
            }
        }).store(in: &cancellables)
        connection?.onDeviceInfoReceived.sink(receiveValue: { deviceInfo in
            Task { @MainActor in
                self.destinationDeviceInfo = deviceInfo
                self.destinationDeviceArchitecture = deviceInfo.appArchitecture
                self.logger.log("migrationController.onDeviceInfoReceived: Destination device architecture: \(deviceInfo.architecture)", type: .default)
            }
        }).store(in: &cancellables)
        connection?.onReadyToReceive.sink(receiveValue: { isReady in
            Task { @MainActor in
                self.connectedDeviceIsReady = isReady
                self.migrationState = .readyForMigration
            }
        }).store(in: &cancellables)
        connection?.onMigrationMetadataReceived.sink(receiveValue: { size in
            Task { @MainActor in
                self.sizeOfMigration = size
            }
        }).store(in: &cancellables)
        connection?.onBytesReceived.sink(receiveValue: { bytesCount in
            Task { @MainActor in
                self.bytesReceived += bytesCount
            }
        }).store(in: &cancellables)
        connection?.onBytesSent.sink(receiveValue: { bytesCount in
            Task { @MainActor in
                self.updateBytesSent(bytesCount)
            }
        }).store(in: &cancellables)
        connection?.onFileSent.sink(receiveValue: { fileCount in
            Task { @MainActor in
                self.updateFilesSent(fileCount)
            }
        }).store(in: &cancellables)
        connection?.onMigrationCompleted.sink(receiveValue: { isCompleted in
            Task { @MainActor in
                self.isMigrationCompleted = isCompleted
                self.migrationState = .completed
            }
        }).store(in: &cancellables)
        connection?.onNewConnectionState.sink(receiveValue: { newState in
            self.connectionState = newState
            switch newState {
            case .setup, .waiting, .preparing:
                Task { @MainActor in
                    guard self.migrationState != .restoringConnection else { return }
                    self.migrationState = .fetching
                    self.isConnected = false
                }
            case .ready:
                Task { @MainActor in
                    self.isConnected = true
                    if self.migrationState == .restoringConnection {
                        self.connectedDeviceIsReady = true
                        self.connectionRestorationAttempts = 0
                        self.logger.log("migrationController.onNewConnectionState: connection restored successfully after \(self.connectionRestorationAttempts) attempts", type: .default)
                        
                        if self.migrationTask != nil && !self.migrationTask!.isCancelled {
                            if !self.migrationOption.migrationFileList.allSatisfy({ $0.sent || !$0.isSelected }) {
                                self.migrationState = .fileMigration
                                self.logger.log("migrationController.onNewConnectionState: resuming file migration", type: .default)
                            } else if !self.migrationOption.migrationAppList.allSatisfy({ $0.migratorFile.sent || !$0.isSelected }) {
                                self.migrationState = .appMigration
                                self.logger.log("migrationController.onNewConnectionState: resuming app migration", type: .default)
                            } else {
                                self.migrationState = .completing
                                self.logger.log("migrationController.onNewConnectionState: resuming migration completion", type: .default)
                            }
                        } else {
                            self.migrationState = .connectionEstablished
                        }
                    } else {
                        self.migrationState = .connectionEstablished
                    }
                }
            case .failed:
                Task { @MainActor in
                    self.connection?.connection.cancel()
                    self.isConnected = false
                    self.migrationState = .restoringConnection
                    self.connectedDeviceIsReady = false
                    self.connectionRestorationAttempts += 1
                    
                    if self.connectionRestorationAttempts > self.maxConnectionRestorationAttempts {
                        self.logger.log("migrationController.onNewConnectionState: exceeded maximum connection restoration attempts (\(self.maxConnectionRestorationAttempts)). Transitioning to interrupted state.", type: .error)
                        self.migrationState = .interrupted
                        MigrationReportController.shared.addError("Connection failed after \(self.maxConnectionRestorationAttempts) restoration attempts")
                    } else {
                        self.logger.log("migrationController.onNewConnectionState: attempting connection restoration (\(self.connectionRestorationAttempts)/\(self.maxConnectionRestorationAttempts))", type: .fault)
                        self.restoreConnection()
                    }
                }
            case .cancelled:
                break
            @unknown default:
                break
            }
        }).store(in: &cancellables)
    }
    
    /// Method used to identify issues during the establishment of a connection.
    /// Needed because the Network framework doesn't give us a simple way to be notified about failed handshakes.
    /// - Parameter attempts: number of attempts the method will make to get an establishment report.
    private func checkConnectionEstablishment(_ attempts: Int) {
        logger.log("migrationController.connect: trying to get connection establishment report...", type: .default)
        self.connection?.connection.requestEstablishmentReport(queue: .global(qos: .userInteractive), completion: { report in
            guard self.connection?.connection.state == .preparing || self.connection?.connection.state == .setup else {
                self.logger.log("migrationController.connect: a connection has been established \"\(self.connection?.connection.debugDescription ?? "nil")\"", type: .default)
                switch self.migrationState {
                case .restoringConnection, .fileMigration, .appMigration, .completing:
                    break
                default:
                    self.migrationState = .fetching
                }
                return
            }
            if report == nil {
                guard attempts > 1 else {
                    self.logger.log("migrationController.connect: failed to get connection establishment report. Connection will be cancelled", type: .error)
                    self.connection?.connection.forceCancel()
                    guard self.migrationState != .restoringConnection else {
                        Task { @MainActor in
                            self.restoreConnection()
                        }
                        return
                    }
                    self.migrationState = .wrongOTPCodeSent
                    return
                }
                self.logger.log("migrationController.connect: failed to get connection establishment report. Trying again in 3 seconds...", type: .fault)
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2), execute: {
                    self.checkConnectionEstablishment(attempts-1)
                })
                return
            }
        })
    }
    
    // MARK: - Resource Management Methods
    
    /// Acquires a resource token for file operations
    func acquireFileOperationToken() async {
        logger.log("migrationController.acquireFileOperationToken: Asking for file operation token...", type: .debug)
        await fileOperationSemaphore.request()
    }
    
    /// Releases a resource token after file operations
    func releaseFileOperationToken() async {
        logger.log("migrationController.releaseFileOperationToken: releasing file operation token...", type: .debug)
        await fileOperationSemaphore.release()
    }
    
    /// Acquires a resource token for file operations
    func acquireConnectionOperationToken() async {
        logger.log("migrationController.acquireConnectionOperationToken: Asking for connection operation token...", type: .debug)
        await self.connectionOperationSemaphore.request()
    }
    
    /// Releases a resource token after file operations
    func releaseConnectionOperationToken() async {
        logger.log("migrationController.releaseConnectionOperationToken: releasing connection operation token...", type: .debug)
        await connectionOperationSemaphore.release()
    }
    
    /// Hold the caller until the migration is in an "in progress" state.
    func awaitConnectionReadiness() async {
        func isMigrationInProgress() -> Bool {
            switch self.migrationState {
            case .paused, .restoringConnection, .cancelled, .discovery, .initial, .interrupted, .wrongOTPCodeSent:
                return false
            default:
                return true
            }
        }
        var canContinue: Bool = isMigrationInProgress()
        while !canContinue {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            canContinue = isMigrationInProgress()
        }
    }
    
    // MARK: - Data Transfer Report Methods
    
    /// Starts the data transfer report collection and timer.
    @MainActor
    func startDataTransferReport() {
        guard let connection = connection?.connection else {
            logger.log("migrationController.startDataTransferReport: no connection available", type: .error)
            return
        }
        
        logger.log("migrationController.startDataTransferReport: starting data transfer report collection", type: .default)
        migrationStartTime = Date()
        pendingDataTrasferReport = connection.startDataTransferReport()
        dataTransferReportTimer = Timer.scheduledTimer(timeInterval: 10, target: self, selector: #selector(estimateTimeLeft), userInfo: nil, repeats: false)
    }
    
    /// Stops the data transfer report collection and timer.
    @MainActor
    func stopDataTransferReport() {
        logger.log("migrationController.stopDataTransferReport: stopping data transfer report collection", type: .default)
        pendingDataTrasferReport = nil
        dataTransferReportTimer?.invalidate()
        dataTransferReportTimer = nil
        migrationStartTime = nil
    }
    
    /// Updates the bytes sent counter.
    @MainActor
    func updateBytesSent(_ bytes: Int) {
        bytesSent += bytes
    }
    
    /// Updates the files sent counter.
    @MainActor
    func updateFilesSent(_ count: Int) {
        filesSent += count
    }
    
    /// Estimates the time left for the migration based on data transfer reports.
    @objc
    private func estimateTimeLeft() {
        guard let migrationOption = migrationOption else {
            logger.log("migrationController.estimateTimeLeft: no migration option available", type: .error)
            return
        }
        
        pendingDataTrasferReport?.collect(queue: .main, completion: { [weak self] report in
            guard let self = self else { return }
            
            if let currentReport = report.pathReports.first(where: { self.connection?.connection.currentPath?.usesInterfaceType($0.interface.type) ?? false }) {
                let transferSpeed = Double(currentReport.sentTransportByteCount)/report.duration
                let timeLeftToTransferBytes = Double(migrationOption.size - self.bytesSent)/transferSpeed
                let rttNeededTime = Double(max(0, migrationOption.numberOfFiles - self.filesSent)) * currentReport.transportSmoothedRTT
                let totalTimeLeft = timeLeftToTransferBytes + rttNeededTime
                
                Task { @MainActor in
                    self.estimatedTimeLeft = String(format: "migration.page.time.estimation.label".localized, totalTimeLeft.prettyFormattedTimeLeft())
                    if transferSpeed.isFinite && !transferSpeed.isNaN {
                        self.transferSpeed = "\(Int(transferSpeed / 1_000_000)) MB/s"
                    } else {
                        self.transferSpeed = "Impossible to estimate..."
                    }
                }
            }
            self.pendingDataTrasferReport = self.connection?.connection.startDataTransferReport()
            self.dataTransferReportTimer?.invalidate()
            self.dataTransferReportTimer = nil
            self.dataTransferReportTimer = Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(self.estimateTimeLeft), userInfo: nil, repeats: false)
        })
    }
    
    // MARK: - Migration Execution Methods
    
    /// Validates app selection and checks for incompatible apps based on destination architecture
    /// - Returns: True if migration can proceed, false if user confirmation is needed
    @MainActor
    func validateAppSelection() -> Bool {
        // Check if architecture validation is enabled via configuration
        guard AppContext.shouldValidateAppsArchitecture else {
            logger.log("migrationController.validateAppSelection: Architecture check is disabled via configuration", type: .default)
            return true
        }
        
        guard let migrationOption = migrationOption else { return true }
        guard let destinationArch = destinationDeviceArchitecture else { return true }
        
        // Find incompatible apps based on destination architecture
        let incompatibleApps: [DiscoveredApplication]
        
        if destinationArch == .appleSilicon {
            // Intel-only apps won't run natively on Apple Silicon
            incompatibleApps = migrationOption.migrationAppList.filter {
                $0.isSelected && $0.architectureType == .intelOnly
            }
            
            if !incompatibleApps.isEmpty {
                logger.log("migrationController.validateAppSelection: Found \(incompatibleApps.count) Intel-only apps selected for Apple Silicon destination", type: .default)
                intelOnlyAppsForConfirmation = incompatibleApps
                shouldShowIntelAppWarning = true
                return false
            }
        } else if destinationArch == .intel {
            // Apple Silicon-only apps won't run on Intel
            incompatibleApps = migrationOption.migrationAppList.filter {
                $0.isSelected && $0.architectureType == .appleSiliconOnly
            }
            
            if !incompatibleApps.isEmpty {
                logger.log("migrationController.validateAppSelection: Found \(incompatibleApps.count) Apple Silicon-only apps selected for Intel destination", type: .default)
                intelOnlyAppsForConfirmation = incompatibleApps
                shouldShowIntelAppWarning = true
                return false
            }
        }
        
        return true
    }
    
    /// Cancels migration due to Intel app concerns
    @MainActor
    func resetIntelAppMigration() {
        shouldShowIntelAppWarning = false
        intelOnlyAppsForConfirmation = []
        logger.log("migrationController.cancelIntelAppMigration: User cancelled migration due to Intel-only apps", type: .default)
    }
    
    @MainActor
    func removeIncompatibleApps(_ completion: (Bool) -> Void) {
        guard !intelOnlyAppsForConfirmation.isEmpty else {
            completion(true)
            return
        }
        migrationOption.migrationAppList.forEach { app in
            if intelOnlyAppsForConfirmation.contains(where: { app.name == $0.name }) {
                app.isSelected = false
            }
        }
        var anyAppSelected = false
        var anyFileSelected = false
        anyAppSelected = migrationOption.migrationAppList.reduce(anyAppSelected, { $0 || $1.isSelected })
        anyFileSelected = migrationOption.migrationFileList.reduce(anyFileSelected, { $0 || $1.isSelected })
        guard anyAppSelected || anyFileSelected else {
            completion(false)
            return
        }
        completion(true)
    }
    
    // swiftlint:disable function_body_length
    /// Starts the migration process.
    @MainActor
    func startMigration() {
        guard let migrationOption = migrationOption else {
            logger.log("migrationController.startMigration: no migration option available", type: .error)
            return
        }

        logger.log("migrationController.startMigration: starting migration", type: .default)
        
        bytesSent = migrationOption.migrationFileList.reduce(1) { $0 + ($1.sent ? $1.fileSize : 0) }
        bytesSent = migrationOption.migrationAppList.reduce(bytesSent) { $0 + ($1.migratorFile.sent ? $1.migratorFile.fileSize : 0) }
        estimatedTimeLeft = String(format: "migration.page.time.estimation.label".localized, "migration.common.calculating.label".localized)
        
        MigrationReportController.shared.setMigrationSize(Int64(migrationOption.size))
        sleep(3)
        
        startDataTransferReport()
        
        migrationTask = Task {
            do {
                try await self.sendMigrationSize(migrationOption.size)
            } catch {
                self.logger.log("migrationController.startMigration: delivery of migration size failed with error \"\(error.localizedDescription)\"", type: .error)
            }

            if migrationOption.migrationPreferencesList.isEmpty && !migrationOption.type.migratePreferences {
                do {
                    try await self.sendDefaults(DefaultsMessage(key: AppContext.skipRebootUserDefaultsKey, boolValue: true))
                } catch {
                    self.logger.log("migrationController.startMigration: delivery of default value failed with error \"\(error.localizedDescription)\"", type: .error)
                }
            }
            
            self.logger.log("migrationController.startMigration: starting migration of files", type: .default)
            await MainActor.run { self.migrationState = .fileMigration }
            
            for file in migrationOption.migrationFileList {
                guard !file.sent && file.isSelected else { continue }
                do {
                    MLogger.main.log("migrationController.startMigration: sending file \(file.url.fullURL().relativePath)", type: .default)
                    try await self.sendFile(file)
                    MLogger.main.log("migrationController.startMigration: file sent \(file.url.fullURL().relativePath)", type: .default)
                    file.sent = true
                    MigrationReportController.shared.addMigratedFile(file.url.fullURL().relativePath)
                } catch {
                    self.logger.log("migrationController.startMigration: failed to send file: \(file.url.fullURL().relativePath) - with error: \"\(error.localizedDescription)\"", type: .error)
                    MigrationReportController.shared.addError("migrationController.startMigration: failed to send file: \(file.url.fullURL().relativePath) - with error: \"\(error.localizedDescription)\"")
                }
            }
            
            self.logger.log("migrationController.startMigration: files migration complete", type: .default)
            self.logger.log("migrationController.startMigration: starting migration of apps", type: .default)
            await MainActor.run { self.migrationState = .appMigration }
            
            for app in migrationOption.migrationAppList {
                guard !app.migratorFile.sent && app.isSelected else { continue }
                do {
                    self.logger.log("migrationController.startMigration: sending app: \(app.migratorFile.url.fullURL().relativePath)", type: .default)
                    try await self.sendFile(app.migratorFile)
                    self.logger.log("migrationController.startMigration: app sent: \(app.migratorFile.url.fullURL().relativePath)", type: .default)
                    app.migratorFile.sent = true
                } catch {
                    self.logger.log("migrationController.startMigration: failed to send file: \(app.migratorFile.url.fullURL().relativePath) - with error: \"\(error.localizedDescription)\"", type: .error)
                    MigrationReportController.shared.addError("migrationController.startMigration: failed to send file: \(app.migratorFile.url.fullURL().relativePath) - with error: \"\(error.localizedDescription)\"")
                }
            }
            
            self.logger.log("migrationController.startMigration: apps migration complete", type: .default)
            await MainActor.run { self.migrationState = .completing }
            
            // Verification and retry phase - ensure all selected items were migrated
            self.logger.log("migrationController.startMigration: starting verification phase", type: .default)
            let verificationResult = await self.verifyAndRetryMigration(migrationOption: migrationOption, maxRetries: 3)
            
            if !verificationResult.success {
                self.logger.log("migrationController.startMigration: verification failed - \(verificationResult.failedItems.count) items could not be migrated", type: .error)
                for failedItem in verificationResult.failedItems {
                    MigrationReportController.shared.addError("Failed to migrate after retries: \(failedItem)")
                }
            } else {
                self.logger.log("migrationController.startMigration: verification complete - all items migrated successfully", type: .default)
            }
            
            do {
                try await self.sendMigrationCompleted()
                MigrationReportController.shared.setMigrationEnd()
                await MainActor.run {
                    self.percentageCompleted = "100%"
                    self.estimatedTimeLeft = ""
                    self.migrationProgress = 1
                    self.stopDataTransferReport()
                    NSSound(named: .init("Funk"))?.play()
                    Utils.Window.makeWindowFloating()
                }
            } catch {
                self.logger.log("migrationController.startMigration: send migration completion failed with error \"\(error.localizedDescription)\"", type: .error)
            }
        }
    }
    // swiftlint:enable function_body_length
    
    /// Verifies that all selected items have been migrated and retries failed items
    /// - Parameters:
    ///   - migrationOption: The migration option containing files and apps to verify
    ///   - maxRetries: Maximum number of retry attempts per item
    /// - Returns: A tuple containing success status and list of failed items
    private func verifyAndRetryMigration(migrationOption: MigrationOption, maxRetries: Int) async -> (success: Bool, failedItems: [String]) {
        logger.log("migrationController.verifyAndRetryMigration: starting verification with max \(maxRetries) retries per item", type: .default)
        
        var failedItems: [String] = []
        var itemRetryCount: [String: Int] = [:]
        var hasUnsentItems = true
        var verificationPass = 0
        let maxVerificationPasses = maxRetries + 1
        
        while hasUnsentItems && verificationPass < maxVerificationPasses {
            verificationPass += 1
            hasUnsentItems = false
            
            logger.log("migrationController.verifyAndRetryMigration: verification pass \(verificationPass)/\(maxVerificationPasses)", type: .default)
            
            let unsentFiles = migrationOption.migrationFileList.filter { !$0.sent && $0.isSelected }
            if !unsentFiles.isEmpty {
                hasUnsentItems = true
                logger.log("migrationController.verifyAndRetryMigration: found \(unsentFiles.count) unsent files", type: .default)
                
                for file in unsentFiles {
                    let itemPath = file.url.fullURL().relativePath
                    let currentRetries = itemRetryCount[itemPath, default: 0]
                    
                    if currentRetries >= maxRetries {
                        logger.log("migrationController.verifyAndRetryMigration: file \(itemPath) exceeded retry limit (\(currentRetries)/\(maxRetries))", type: .error)
                        if !failedItems.contains(itemPath) {
                            failedItems.append(itemPath)
                        }
                        continue
                    }
                    
                    itemRetryCount[itemPath] = currentRetries + 1
                    
                    do {
                        logger.log("migrationController.verifyAndRetryMigration: retrying file \(itemPath) (attempt \(currentRetries + 1)/\(maxRetries))", type: .default)
                        try await MigrationController.shared.sendFile(file)
                        file.sent = true
                        MigrationReportController.shared.addMigratedFile(itemPath)
                        logger.log("migrationController.verifyAndRetryMigration: successfully sent file \(itemPath)", type: .default)
                    } catch {
                        logger.log("migrationController.verifyAndRetryMigration: failed to send file \(itemPath) - \(error.localizedDescription)", type: .error)
                    }
                }
            }
            
            let unsentApps = migrationOption.migrationAppList.filter { !$0.migratorFile.sent && $0.isSelected }
            if !unsentApps.isEmpty {
                hasUnsentItems = true
                logger.log("migrationController.verifyAndRetryMigration: found \(unsentApps.count) unsent apps", type: .default)
                
                for app in unsentApps {
                    let itemPath = app.url.relativePath
                    let currentRetries = itemRetryCount[itemPath, default: 0]
                    
                    if currentRetries >= maxRetries {
                        logger.log("migrationController.verifyAndRetryMigration: app \(itemPath) exceeded retry limit (\(currentRetries)/\(maxRetries))", type: .error)
                        if !failedItems.contains(itemPath) {
                            failedItems.append(itemPath)
                        }
                        continue
                    }
                    
                    itemRetryCount[itemPath] = currentRetries + 1
                    
                    do {
                        logger.log("migrationController.verifyAndRetryMigration: retrying app \(itemPath) (attempt \(currentRetries + 1)/\(maxRetries))", type: .default)
                        try await MigrationController.shared.sendFile(app.migratorFile)
                        app.migratorFile.sent = true
                        logger.log("migrationController.verifyAndRetryMigration: successfully sent app \(itemPath)", type: .default)
                    } catch {
                        logger.log("migrationController.verifyAndRetryMigration: failed to send app \(itemPath) - \(error.localizedDescription)", type: .error)
                    }
                }
            }
            
            if hasUnsentItems && verificationPass < maxVerificationPasses {
                logger.log("migrationController.verifyAndRetryMigration: waiting 5 seconds before next verification pass", type: .default)
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            }
        }
        
        let finalUnsentFiles = migrationOption.migrationFileList.filter { !$0.sent && $0.isSelected }
        let finalUnsentApps = migrationOption.migrationAppList.filter { !$0.migratorFile.sent && $0.isSelected }
        
        for file in finalUnsentFiles {
            let itemPath = file.url.fullURL().relativePath
            if !failedItems.contains(itemPath) {
                failedItems.append(itemPath)
            }
        }
        
        for app in finalUnsentApps {
            let itemPath = app.url.relativePath
            if !failedItems.contains(itemPath) {
                failedItems.append(itemPath)
            }
        }
        
        let success = failedItems.isEmpty
        logger.log("migrationController.verifyAndRetryMigration: verification complete - success: \(success), failed items: \(failedItems.count)", type: success ? .default : .error)
        
        return (success: success, failedItems: failedItems)
    }
    
    // MARK: - Connection Wrapper Methods
    
    /// Sends a file through the current active connection
    /// - Parameter file: The file to send
    func sendFile(_ file: MigratorFile) async throws {
        guard let currentConnection = connection else {
            logger.log("migrationController.sendFile: no active connection", type: .error)
            throw NSError(domain: "MigrationController", code: 2001,
                         userInfo: [NSLocalizedDescriptionKey: "No active connection"])
        }
        try await currentConnection.sendFile(file)
    }
    
    /// Sends migration size through the current active connection
    /// - Parameter size: The size to send
    func sendMigrationSize(_ size: Int) async throws {
        guard let currentConnection = connection else {
            logger.log("migrationController.sendMigrationSize: no active connection", type: .error)
            throw NSError(domain: "MigrationController", code: 2001,
                         userInfo: [NSLocalizedDescriptionKey: "No active connection"])
        }
        try await currentConnection.sendMigrationSize(size)
    }
    
    /// Sends defaults through the current active connection
    /// - Parameter object: The defaults message to send
    func sendDefaults(_ object: DefaultsMessage) async throws {
        guard let currentConnection = connection else {
            logger.log("migrationController.sendDefaults: no active connection", type: .error)
            throw NSError(domain: "MigrationController", code: 2001,
                         userInfo: [NSLocalizedDescriptionKey: "No active connection"])
        }
        try await currentConnection.sendDefaults(object)
    }
    
    /// Sends migration completed through the current active connection
    func sendMigrationCompleted() async throws {
        guard let currentConnection = connection else {
            logger.log("migrationController.sendMigrationCompleted: no active connection", type: .error)
            throw NSError(domain: "MigrationController", code: 2001,
                         userInfo: [NSLocalizedDescriptionKey: "No active connection"])
        }
        try await currentConnection.sendMigrationCompleted()
    }
    
    /// Pauses the migration process.
    @MainActor
    func pauseMigration() {
        logger.log("migrationController.pauseMigration: pausing migration", type: .default)
        migrationTask?.cancel()
        stopDataTransferReport()
        
        if migrationState != .completed && migrationState != .interrupted {
            migrationState = .paused
            MigrationReportController.shared.addError("migrationController.pauseMigration: Migration was paused by user or system")
        }
    }
}
// swiftlint:enable type_body_length file_length
