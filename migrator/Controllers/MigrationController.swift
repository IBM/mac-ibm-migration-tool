//
//  MigrationController.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 01/02/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import Network
import Combine

/// Controls the migration process, managing network connections, and handling data transfer.
class MigrationController: ObservableObject {
    
    // MARK: - Enum Definitions
    
    enum MigrationState {
        case initial
        case discovery
        case fetching
        case readyForMigration
        case fileMigration
        case appMigration
        case preferencesMigration
        case interrupted
        case paused
        case restoring
        case completing
        case completed
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
                switch newState {
                case .setup, .waiting, .preparing:
                    Task { @MainActor in
                        self.connectionState = newState
                        self.isConnected = false
                    }
                case .ready:
                    Task { @MainActor in
                        self.isConnected = true
                        self.connectionState = newState
                    }
                case .failed:
                    Task { @MainActor in
                        self.connection?.connection.cancel()
                        self.connection = nil
                        self.connectionState = newState
                        self.connectionState = .setup
                        self.isConnected = false
                        self.migrationState = .interrupted
                    }
                case .cancelled:
                    Task { @MainActor in
                        self.connection = nil
                        self.connectionState = newState
                        self.connectionState = .setup
                        self.isConnected = false
                        self.migrationState = .interrupted
                    }
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
    
    // MARK: - Private Variables
    
    /// Collection of cancellable subscriptions to manage memory and avoid retain cycles.
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Private Constants
    
    /// Logger instance.
    private let logger: MLogger = MLogger.main
    
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
    /// Tracks connection states.
    @Published var connectionState: NWConnection.State = .setup
    /// Tracks migration controller state.
    @Published var migrationState: MigrationState = .initial
            
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
    }
    
    /// Starts the network server to accept incoming connections with a given passcode.
    @MainActor
    func startServer(withPasscode passcode: String) {
        logger.log("migrationController.networkServer.start: starting server with passcode \"\(passcode)\"...", type: .default)
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
        logger.log("migrationController.networkBrowser.start: starting browser...", type: .default)
        browser.start()
        migrationState = .discovery
    }
    
    /// Stops the network browser, ending the search for network services.
    @MainActor
    func stopBrowser() {
        logger.log("migrationController.networkBrowser.stop: stopping the  browser...", type: .default)
        browser.stop()
        migrationState = .initial
        browserResults = []
    }
    
    /// Attempts to connect to a specified device using a passcode. Calls the completion handler with the result.
    @MainActor 
    func connect(to device: NWBrowser.Result, withPasscode passcode: String = "000000", completion: @escaping (Bool) -> Void) {
        logger.log("migrationController.connect: starting connection with device \"\(device)\", using passcode \"\(passcode)\"", type: .default)
        guard self.connection == nil else {
            logger.log("migrationController.connect: a connection has already been established \"\(self.connection?.connection.debugDescription ?? "nil")\", discarding new connection request...", type: .default)
            completion(true)
            return
        }

        // Stops browsing to focus on establishing the connection.
        self.stopBrowser()
        
        // Creates a new connection to the selected device.
        self.connection = NetworkConnection(endpoint: device.endpoint, withPasscode: passcode)
        self.connection?.connection.start(queue: .main)
        logger.log("migrationController.connect: starting connection...", type: .default)
        self.hostName = device.resultName
        self.checkConnectionEstablishment(5)
        
        // Calls completion with success after setting up the connection.
        completion(true)
    }
    
    @MainActor 
    func resetMigration() {
        self.stopServer()
        self.stopBrowser()
        self.connection?.connection.forceCancel()
        self.connection = nil
        self.migrationOption = nil
        self.migrationProgress = 0
        self.sizeOfMigration = 0
        self.browserResults = []
        self.selectedBrowserResult = nil
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
}
