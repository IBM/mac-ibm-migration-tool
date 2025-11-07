//
//  MigrationController.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 01/02/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import Network
import Combine
import Darwin

// swiftlint:disable type_body_length file_length
/// Controls the migration process, managing network connections, and handling data transfer.
class MigrationController: ObservableObject {
    
    // MARK: - Resource Monitoring Constants
    
    /// Maximum number of files to process in parallel
    private let maxConcurrentFileOperations = 5
    
    /// Interval in seconds to check system resources
    private let resourceCheckInterval: TimeInterval = 10.0
    
    /// Minimum free memory required (in bytes) - 500 MB
    private let minimumFreeMemory: UInt64 = 500 * 1024 * 1024
    
    /// Maximum memory usage percentage before pausing (0.0-1.0)
    private let maxMemoryUsagePercentage: Double = 0.85
    
    /// Timer for periodic resource checks
    private var resourceMonitorTimer: Timer?
    
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
            // Subscribes to hostname changes on the current connection and updates the local hostname property.
            connection?.onHostNameChange.sink(receiveValue: { hostName in
                Task { @MainActor in
                    self.hostName = hostName
                    self.migrationState = .readyForMigration
                    MigrationReportController.shared.setTargetDevice(hostName)
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
                        }
                        self.migrationState = .connectionEstablished
                    }
                case .failed:
                    Task { @MainActor in
                        self.connection?.connection.cancel()
                        self.isConnected = false
                        self.migrationState = .restoringConnection
                        self.connectedDeviceIsReady = false
                        self.restoreConnection()
                    }
                case .cancelled:
                    break
                @unknown default:
                    break
                }
            }).store(in: &cancellables)
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
    
    private var destinationDevice: NWBrowser.Result!
    /// Tracks connection states.
    private var connectionState: NWConnection.State = .setup
    
    // MARK: - Private Constants
    
    /// Logger instance.
    private let logger: MLogger = MLogger.main
    /// Flag to indicate if migration is paused due to resource constraints
    private var isPausedForResources: Bool = false
    /// Queue for managing file operations
    private let fileOperationQueue = DispatchQueue(label: "com.ibm.migrator.fileOperations",
                                                 attributes: .concurrent)
    /// Semaphore to limit concurrent file operations
    private let fileOperationSemaphore = DispatchSemaphore(value: 5)
    /// Queue for managing connection operations
    private let connectionOperationQueue = DispatchQueue(label: "com.ibm.migrator.connectionOperations",
                                                   attributes: .concurrent)
    /// Semaphore to limit concurrent file operations
    private let connectionOperationSemaphore = DispatchSemaphore(value: 5)
    
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
        // startResourceMonitoring() Thinking it to enable a resource monitoring logic...
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
        
        // Creates a new connection to the selected device.
        self.connection = NetworkConnection(endpoint: device.endpoint, withPasscode: passcode)
        self.connection?.connection.start(queue: .main)
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
        stopResourceMonitoring()
        isPausedForResources = false
        migrationSetupViewModel.resetMigration()
    }
    
    @MainActor
    func restoreConnection() {
        switch self.operatingMode {
        case .server:
            self.startServer(withPasscode: self.passcode)
        case .browser:
            self.connect(to: self.destinationDevice, withPasscode: self.passcode)
        case .none:
            break
        }
    }
    
    // MARK: - Private Methods
    
    /// Method used to identify issues during the establishment of a connection.
    /// Needed because the Network framework doesn't give us a simple way to be notified about failed handshakes.
    /// - Parameter attempts: number of attempts the method will make to get an establishment report.
    private func checkConnectionEstablishment(_ attempts: Int) {
        logger.log("migrationController.connect: trying to get connection establishment report...", type: .default)
        self.connection?.connection.requestEstablishmentReport(queue: .global(qos: .userInteractive), completion: { report in
            guard self.connection?.connection.state == .preparing || self.connection?.connection.state == .setup else {
                self.logger.log("migrationController.connect: a connection has been established \"\(self.connection?.connection.debugDescription ?? "nil")\"", type: .default)
                self.migrationState = .fetching
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
    
    /// Starts periodic monitoring of system resources
    private func startResourceMonitoring() {
        logger.log("migrationController.startResourceMonitoring: Starting resource monitoring", type: .default)
        checkSystemResources()
        resourceMonitorTimer = Timer.scheduledTimer(withTimeInterval: resourceCheckInterval, repeats: true) { [weak self] _ in
            self?.checkSystemResources()
        }
    }
    
    /// Stops resource monitoring
    private func stopResourceMonitoring() {
        logger.log("migrationController.stopResourceMonitoring: Stopping resource monitoring", type: .default)
        resourceMonitorTimer?.invalidate()
        resourceMonitorTimer = nil
    }
    
    /// Checks system resources and adjusts migration behavior accordingly
    private func checkSystemResources() {
        // Check available memory
        let memoryInfo = getMemoryInfo()
        let freeMemory = memoryInfo.free
        let totalMemory = memoryInfo.total
        let memoryUsagePercentage = Double(totalMemory - freeMemory) / Double(totalMemory)
        
        logger.log("migrationController.checkSystemResources: Memory usage: \(Int(memoryUsagePercentage * 100))%, Free: \(freeMemory / 1024 / 1024) MB", type: .default)
        
        // Check if we need to pause due to low resources
        if freeMemory < minimumFreeMemory || memoryUsagePercentage > maxMemoryUsagePercentage {
            if !isPausedForResources {
                logger.log("migrationController.checkSystemResources: Pausing migration due to low system resources", type: .fault)
                isPausedForResources = true
                
                for _ in 0..<3 {
                    fileOperationSemaphore.wait()
                }
                
                Task { @MainActor in
                    self.migrationState = .paused
                }
            }
        } else if isPausedForResources {
            // Resume if we have enough resources now
            logger.log("migrationController.checkSystemResources: Resuming migration after resource constraints", type: .default)
            isPausedForResources = false
            
            // Restore semaphore
            for _ in 0..<3 {
                fileOperationSemaphore.signal()
            }
            
            Task { @MainActor in
                if self.migrationState == .paused {
                    self.migrationState = .fileMigration
                }
            }
        }
    }
    
    /// Gets information about system memory usage
    private func getMemoryInfo() -> (free: UInt64, total: UInt64) {
        var pageSize: vm_size_t = 0
        let hostPort: mach_port_t = mach_host_self()
        var hostSize: mach_msg_type_number_t = mach_msg_type_number_t(MemoryLayout<vm_statistics_data_t>.stride / MemoryLayout<integer_t>.stride)
        var vmStats = vm_statistics_data_t()

        _ = withUnsafeMutablePointer(to: &vmStats) { vmStatsPtr -> kern_return_t in
            return vmStatsPtr.withMemoryRebound(to: integer_t.self, capacity: Int(hostSize)) { intPtr in
                host_statistics(hostPort, HOST_VM_INFO, intPtr, &hostSize)
            }
        }

        host_page_size(hostPort, &pageSize)

        let freeMemory = UInt64(vmStats.free_count) * UInt64(pageSize)
        let totalMemory = ProcessInfo.processInfo.physicalMemory

        return (freeMemory, totalMemory)
    }
    
    /// Acquires a resource token for file operations
    func acquireFileOperationToken() async {
        logger.log("migrationController.acquireFileOperationToken: Asking for file operation token...", type: .debug)
        await withCheckedContinuation { continuation in
            self.fileOperationQueue.async {
                self.fileOperationSemaphore.wait()
                continuation.resume()
            }
        }
    }
    
    /// Releases a resource token after file operations
    func releaseFileOperationToken() {
        logger.log("migrationController.releaseFileOperationToken: releasing file operation token...", type: .debug)
        fileOperationSemaphore.signal()
    }
    
    /// Acquires a resource token for file operations
    func acquireConnectionOperationToken() async {
        logger.log("migrationController.acquireConnectionOperationToken: Asking for connection operation token...", type: .debug)
        await withCheckedContinuation { continuation in
            self.connectionOperationQueue.async {
                self.connectionOperationSemaphore.wait()
                continuation.resume()
            }
        }
    }
    
    /// Releases a resource token after file operations
    func releaseConnectionOperationToken() {
        logger.log("migrationController.releaseConnectionOperationToken: releasing connection operation token...", type: .debug)
        connectionOperationSemaphore.signal()
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
}
// swiftlint:enable type_body_length file_length
