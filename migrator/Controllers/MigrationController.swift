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

// swiftlint:disable type_body_length file_length large_tuple
/// Controls the migration process, managing network connections, and handling data transfer.
@MainActor
final class MigrationController: ObservableObject {
    
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
            // A promoted racing predecessor is already subscribed from when it was first assigned.
            guard !isPromotingRacingPredecessor else { return }
            self.setupSubscriptions()
        }
    }
    /// Set while `promoteRacingPredecessor` re-assigns `connection`, so its subscriptions aren't duplicated.
    private var isPromotingRacingPredecessor = false
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
    /// Tracks how many pairing attempts a human has accepted but then failed the code check on,
    /// across the current server session.
    private var failedPairingAttempts: Int = 0
    /// Maximum number of failed pairing attempts before the server locks and requires a new code.
    private let maxFailedPairingAttempts: Int = 5
    /// Server only: the remote host of the last pairing request the destination human
    /// explicitly accepted this server session.
    private(set) var lastAcceptedPairingHost: NWEndpoint.Host?
    /// Timer that samples the transfer progress once per second to feed the time-left estimate.
    private var etaSampleTimer: Timer?
    /// Learns the cost of a byte and of a file from the transfer to estimate the time left.
    private var etaEstimator = MigrationETAEstimator()
    /// Smooths the estimate before it is shown.
    private var etaStabilizer = ETADisplayStabilizer()
    /// Progress counters at the previous ETA sample, `nil` until the first sample after a (re)start.
    private var lastETASample: (date: Date, bytes: Int, files: Int)?
    /// Counts ETA samples, used to log the progress periodically.
    private var etaSampleCount: Int = 0
    /// Timer driving the connection-health watchdog. Independent of the ETA sampling timer -
    /// the watchdog needs a fixed, predictable cadence to make its stalled-window count meaningful.
    private var connectionHealthWatchdogTimer: Timer?
    /// Object used to collect data transfer reports for the connection-health watchdog, separate
    /// from the ETA sampling, which no longer relies on transfer reports.
    private var pendingHealthCheckReport: NWConnection.PendingDataTransferReport?
    /// Whether a health-check report collection is still outstanding. If the watchdog timer fires
    /// again before the previous collection has come back, that's treated as a stalled window too.
    private var isHealthCheckReportPending: Bool = false
    /// Number of consecutive watchdog windows observed with ~zero transport bytes sent while
    /// actively transmitting.
    private var consecutiveStalledWindows: Int = 0
    /// How often the connection-health watchdog samples throughput.
    private let connectionHealthCheckInterval: TimeInterval = 10
    /// Consecutive stalled windows (at `connectionHealthCheckInterval` each) before the connection
    /// is considered broken and repair is attempted. 12 * 10s = 2 minutes.
    private let maxConsecutiveStalledWindows: Int = 12
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
    private let logger = MLogger.main.scoped(to: .migration)
    /// Flag to indicate if migration is paused due to resource constraints
    private var isPausedForResources: Bool = false
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
    /// Server only: which pairing-related alert, if any, should be shown.
    enum PendingPairingAlert: Equatable {
        case none
        case requestPending(hostname: String)
        case accepted
    }
    @Published var pendingPairingAlert: PendingPairingAlert = .none
    /// Client only: whether the destination has accepted this device's `pairingRequest`, so
    /// the code entry field should be unlocked. `false` means "don't let the human type or
    /// submit a code yet - nobody has agreed to check it."
    @Published var isAwaitingPasscodeEntry: Bool = false
    /// Client only: whether the destination declined (or never answered) this device's
    /// `pairingRequest`. Distinct from `.wrongOTPCodeSent`, since no code was entered yet.
    @Published var pairingRequestWasDeclined: Bool = false
    /// Server only: whether repeated wrong-code attempts locked the server. The listener is
    /// stopped; the human must generate a new code to resume.
    @Published var isPairingLocked: Bool = false
    /// Source only: a user-requested pause is waiting for the in-flight chunk to finish before
    /// the connection is closed.
    @Published var isPausing: Bool = false
    /// Source only: the last attempt to resume a paused migration couldn't reach the destination.
    @Published var resumeFailed: Bool = false
    /// Source only: a user-requested resume is reconnecting. Makes a failed reconnect fall back
    /// to `.paused` instead of `.interrupted`.
    private var isResumingFromPause: Bool = false
    /// Gives up a resume that never reaches `.ready` (e.g. the destination isn't on this network).
    private var resumeTimeoutTask: Task<Void, Never>?
    /// How long a resume may take before it's treated as failed.
    private let resumeTimeout: TimeInterval = 60
    /// Server only: an incoming connection replaced by a newer one moments later, kept until we
    /// know which of the two the source actually uses (see `holdRacingPredecessor`).
    private var racingPredecessor: NetworkConnection?
    private var racingPredecessorCancellable: AnyCancellable?
    /// Maximum time `pauseMigration()` waits for in-flight sends to finish.
    private let pauseQuiesceTimeout: TimeInterval = 30

    // MARK: - Initializers
    
    private init() {
        self.server = NetworkServer()
        self.browser = NetworkBrowser()
        
        // Sets up a sink to handle new connections to the server.
        self.server.onNewConnection.sink { [weak self] newConnection in
            self?.logger.log("migrationController.onNewConnection: new connection request received from \"\(newConnection.debugDescription)\"", type: .default)
            // Prevents connecting to the same endpoint more than once.
            if let currentConnection = self?.connection?.connection, currentConnection.endpoint == newConnection.endpoint {
                newConnection.cancel()
            } else if let self, let passcode = self.passcode {
                // The source races IPv6 and IPv4 and the destination sees both as separate
                // incoming connections, in no guaranteed order, with only one of them kept by
                // the source. Hold on to the one about to be replaced until we know which wins.
                self.holdRacingPredecessor(self.connection)
                // Establishes a new connection if the device is different.
                self.connection = NetworkConnection(connection: newConnection, withPasscode: passcode)
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
    
    /// Server: keeps an incoming connection that a newer one is about to replace, in case it
    /// turns out to be the one the source kept. Only a still-undecided connection qualifies -
    /// one that already received a `pairingRequest` or finished authenticating is the real one.
    private func holdRacingPredecessor(_ predecessor: NetworkConnection?) {
        discardRacingPredecessor()
        guard operatingMode == .server, let predecessor,
              !predecessor.isAuthenticated, !predecessor.hasReceivedPairingRequest,
              predecessor.connection.state != .cancelled else { return }
        logger.log("migrationController.holdRacingPredecessor: holding \"\(predecessor.connection.endpoint.debugDescription)\" in case it is the connection the source kept", type: .default)
        racingPredecessor = predecessor
        racingPredecessorCancellable = predecessor.onIncomingPairingRequest.sink { [weak self, weak predecessor] hostname in
            Task { @MainActor in
                guard let self, let predecessor, self.racingPredecessor === predecessor else { return }
                self.promoteRacingPredecessor(hostname: hostname)
            }
        }
    }

    /// Server: drops the held predecessor, which lost the race.
    private func discardRacingPredecessor() {
        racingPredecessorCancellable = nil
        racingPredecessor?.connection.cancel()
        racingPredecessor = nil
    }

    /// Server: the held predecessor received the `pairingRequest`, so it is the connection the
    /// source kept. Makes it current again, discards the newer one that replaced it, and
    /// handles the request it would otherwise have missed.
    @MainActor
    private func promoteRacingPredecessor(hostname: String) {
        guard let winner = racingPredecessor else { return }
        logger.log("migrationController.promoteRacingPredecessor: held connection received the pairing request, making it current", type: .default)
        racingPredecessorCancellable = nil
        racingPredecessor = nil
        let loser = connection
        isPromotingRacingPredecessor = true
        connection = winner
        isPromotingRacingPredecessor = false
        loser?.connection.cancel()
        handleIncomingPairingRequest(hostname: hostname, from: winner)
    }

    /// Server: shows the approval alert for a `pairingRequest`, or auto-accepts it on a
    /// reconnect from a device the human already approved.
    @MainActor
    private func handleIncomingPairingRequest(hostname: String, from requestingConnection: NetworkConnection?) {
        guard connection === requestingConnection else { return }
        // This is the connection the source kept, so any held predecessor lost the race.
        discardRacingPredecessor()
        let remoteHost = connection?.remoteHost
        if migrationState == .restoringConnection || migrationState == .paused || (remoteHost != nil && remoteHost == lastAcceptedPairingHost) {
            acceptCurrentPairingRequest()
        } else {
            pendingPairingAlert = .requestPending(hostname: hostname)
        }
    }

    /// Starts the network server to accept incoming connections with a given passcode. Also
    /// used by `restoreConnection()` to re-listen after a dropped connection - in that case
    /// `migrationState` is already `.restoringConnection` and must stay that way (and
    /// `lastAcceptedPairingHost` must be preserved) so the reconnecting device's `pairingRequest`
    /// gets auto-accepted by the `onIncomingPairingRequest` sink instead of prompting the human
    /// to approve a pairing request they already approved once.
    @MainActor
    func startServer(withPasscode passcode: String) {
        self.operatingMode = .server
        self.passcode = passcode
        let isRestoring = migrationState == .restoringConnection || migrationState == .paused
        if !isRestoring {
            self.lastAcceptedPairingHost = nil
        }
        logger.log("migrationController.networkServer.start: starting server...", type: .default)
        do {
            try server.start()
            if !isRestoring {
                migrationState = .discovery
            }
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

    /// Server: recovers from a wrong-code lockout (see `maxFailedPairingAttempts`) by
    /// generating a fresh code and restarting the listener. Called from the UI's "Generate a
    /// new code" action.
    @MainActor
    func recoverFromPairingLockout(withPasscode passcode: String) {
        failedPairingAttempts = 0
        isPairingLocked = false
        startServer(withPasscode: passcode)
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
    
    /// Attempts to connect to a specified device. The passcode isn't known yet - the device
    /// identifies itself by hostname first, and the code is supplied later via `submitPasscode`
    /// once the destination approves it (see `NetworkConnection.beginPairingHandshake`).
    @MainActor
    func connect(to device: NWBrowser.Result) {
        self.destinationDevice = device
        self.pairingRequestWasDeclined = false
        self.isAwaitingPasscodeEntry = false
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
        
        // Creates a new connection to the selected device (or replaces the existing wrapper -
        // either way this is a fresh `NetworkConnection`, so it starts a fresh pairing).
        self.connection = NetworkConnection(endpoint: device.endpoint)
        self.connection?.connection.start(queue: .main)

        logger.log("migrationController.connect: starting connection...", type: .default)
        self.hostName = device.resultName
        MigrationReportController.shared.setTargetDevice(device.resultName)
    }

    /// Called once the destination has accepted this device's `pairingRequest` and the human
    /// has typed in the code relayed from the destination's screen.
    func submitPasscode(_ passcode: String) async {
        await connection?.submitPasscode(passcode)
    }

    /// Server: the destination human approved the pending `pairingRequest`. Silent on the
    /// wire - switches `pendingPairingAlert` to show the code-and-cancel alert locally instead.
    @MainActor
    func acceptIncomingPairingRequest() {
        guard case .requestPending = pendingPairingAlert else { return }
        acceptCurrentPairingRequest()
    }

    /// Shared by the UI-driven accept above and an auto-accepted mid-migration reconnect or
    /// same-host retry (see the `onIncomingPairingRequest` subscription in `setupSubscriptions`).
    /// The auto-accept path must go through here too, rather than calling
    /// `NetworkConnection.acceptIncomingPairingRequest()` directly - that only tells the client
    /// it may proceed, but never touches `pendingPairingAlert`, which would leave this device's
    /// own screen showing nothing at all.
    @MainActor
    private func acceptCurrentPairingRequest() {
        lastAcceptedPairingHost = connection?.remoteHost
        pendingPairingAlert = .accepted
        connection?.acceptIncomingPairingRequest()
    }

    /// Server: the destination human declined the pending `pairingRequest`. The listener keeps
    /// running for the next attempt.
    @MainActor
    func declineIncomingPairingRequest() {
        pendingPairingAlert = .none
        connection?.declineIncomingPairingRequest()
    }

    /// Server: the destination human cancelled from the code-showing alert, after already
    /// accepting.
    @MainActor
    func cancelAcceptedPairingRequest() {
        pendingPairingAlert = .none
        connection?.cancelAcceptedPairingRequest()
    }

    /// Client: the human cancelled the connection attempt, either while waiting for the
    /// destination's decision or while still entering the code.
    @MainActor
    func cancelPairingRequest() {
        connection?.cancelPairingRequest()
    }

    @MainActor
    func resetMigration() {
        stopServer()
        stopBrowser()
        stopConnectionHealthWatchdog()
        connection?.connection.forceCancel()
        connection = nil
        migrationOption = nil
        migrationProgress = 0
        sizeOfMigration = 0
        browserResults = []
        selectedBrowserResult = nil
        isPausedForResources = false
        connectionRestorationAttempts = 0
        isPausing = false
        resumeFailed = false
        isResumingFromPause = false
        resumeTimeoutTask?.cancel()
        resumeTimeoutTask = nil
        migrationSetupViewModel.resetMigration()
        FileSizeCache.shared.pruneExpiredEntries()
    }
    
    @MainActor
    func restoreConnection() {
        logger.log("migrationController.restoreConnection: attempting to restore connection", type: .default)
        
        switch self.operatingMode {
        case .server:
            logger.log("migrationController.restoreConnection: restarting server", type: .default)
            self.startServer(withPasscode: self.passcode)
        case .browser:
            if let existingConnection = self.connection {
                logger.log("migrationController.restoreConnection: restoring existing connection object", type: .default)
                if existingConnection.restoreConnection() {
                    logger.log("migrationController.restoreConnection: connection restoration initiated", type: .default)
                } else {
                    logger.log("migrationController.restoreConnection: connection restoration failed, falling back to new connection", type: .error)
                    self.connect(to: self.destinationDevice)
                }
            } else {
                logger.log("migrationController.restoreConnection: no existing connection, creating new one", type: .default)
                self.connect(to: self.destinationDevice)
            }
        case .none:
            logger.log("migrationController.restoreConnection: no operating mode set", type: .error)
        }
    }

    /// Repairs a connection that appears broken even though Network.framework hasn't (yet, or
    /// ever will) report a `.failed` state - e.g. the connection-health watchdog detecting zero
    /// throughput, or `NetworkConnection` exhausting its send retries. Also the sole handler for
    /// a real `.failed` state, which now just forwards here.
    ///
    /// Idempotent: `migrationState == .restoringConnection` doubles as an in-progress flag, so
    /// overlapping triggers (the watchdog firing right as a send exhausts its retries, or a
    /// stale `.failed` callback arriving after this method already started a repair) only act
    /// once, and the watchdog resets its own stalled-window count whenever this state is active -
    /// see `performConnectionHealthCheck()`.
    @MainActor
    func attemptConnectionRepair(reason: String) {
        guard migrationState != .restoringConnection else {
            logger.log("migrationController.attemptConnectionRepair: repair already in progress, ignoring (\(reason))", type: .default)
            return
        }
        guard migrationState != .paused else {
            logger.log("migrationController.attemptConnectionRepair: migration is paused, ignoring (\(reason))", type: .default)
            return
        }
        guard connection?.isAuthenticated == true else {
            logger.log("migrationController.attemptConnectionRepair: no authenticated connection to repair (\(reason))", type: .default)
            return
        }
        logger.log("migrationController.attemptConnectionRepair: connection appears unhealthy (\(reason)), attempting repair", type: .error)
        isConnected = false
        migrationState = .restoringConnection
        connectedDeviceIsReady = false
        connectionRestorationAttempts += 1
        connection?.connection.forceCancel()

        if connectionRestorationAttempts > maxConnectionRestorationAttempts {
            logger.log("migrationController.attemptConnectionRepair: exceeded maximum connection restoration attempts (\(maxConnectionRestorationAttempts)). Transitioning to interrupted state.", type: .error)
            if isResumingFromPause {
                failResumeAndReturnToPaused()
                return
            }
            migrationState = .interrupted
            MigrationReportController.shared.addError("Connection failed after \(maxConnectionRestorationAttempts) restoration attempts")
        } else {
            logger.log("migrationController.attemptConnectionRepair: attempting connection restoration (\(connectionRestorationAttempts)/\(maxConnectionRestorationAttempts)) (\(reason))", type: .fault)
            restoreConnection()
        }
    }

    // MARK: - Private Methods
    
    /// Sets up Combine subscriptions for all relevant `NetworkConnection` publishers to keep the
    /// `MigrationController` state synchronized with the underlying connection lifecycle and data flow.
    private func setupSubscriptions() {
        let currentConnection = connection
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
                self.logger.log("migrationController.onDeviceInfoReceived: Connected device info: Architecture - \(deviceInfo.architecture), OS Version - \(deviceInfo.osVersion), Available Space - \(deviceInfo.availableSpace)",
                                type: .default)
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
                    guard self.migrationState != .restoringConnection, self.migrationState != .paused else { return }
                    self.migrationState = .fetching
                    self.isConnected = false
                }
            case .ready:
                Task { @MainActor in
                    self.isConnected = true
                    self.pendingPairingAlert = .none
                    if self.migrationState == .restoringConnection || self.migrationState == .paused {
                        self.connectedDeviceIsReady = true
                        self.connectionRestorationAttempts = 0
                        if self.isResumingFromPause {
                            self.completeResume()
                        }
                        self.logger.log("migrationController.onNewConnectionState: connection restored successfully after \(self.connectionRestorationAttempts) attempts", type: .default)
                        
                        if self.migrationTask != nil && !self.migrationTask!.isCancelled {
                            if !self.migrationOption.migrationFileList.allSatisfy({ $0.sent || !$0.isSelected }) {
                                self.migrationState = .fileMigration
                                self.logger.log("migrationController.onNewConnectionState: resuming file migration", type: .default)
                            } else if !self.migrationOption.migrationAppList.allSatisfy({ $0.migratorFile.sent || !$0.isSelected }) {
                                self.migrationState = .appMigration
                                self.logger.log("migrationController.onNewConnectionState: resuming app migration", type: .default)
                            } else if !self.migrationOption.migrationPreferencesList.allSatisfy({ $0.sent || !$0.isSelected }) {
                                self.migrationState = .preferencesMigration
                                self.logger.log("migrationController.onNewConnectionState: resuming preferences migration", type: .default)
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
                    self.attemptConnectionRepair(reason: "connection reported .failed")
                }
            case .cancelled:
                break
            @unknown default:
                break
            }
        }).store(in: &cancellables)
        connection?.onAuthenticationFailed.sink(receiveValue: { [weak self] reason in
            guard let self else { return }
            self.logger.log("migrationController.onAuthenticationFailed: application-layer pairing handshake failed (reason: \(reason))", type: .error)
            Task { @MainActor in
                guard self.connection === currentConnection else { return }
                switch self.operatingMode {
                case .server:
                    if reason == .wrongCode {
                        self.failedPairingAttempts += 1
                    } else {
                        self.pendingPairingAlert = .none
                    }
                    if self.failedPairingAttempts >= self.maxFailedPairingAttempts {
                        self.logger.log("migrationController.onAuthenticationFailed: exceeded maximum failed pairing attempts (\(self.maxFailedPairingAttempts)), locking the server", type: .error)
                        self.server.stop()
                        self.isServiceRegistered = false
                        self.isPairingLocked = true
                        self.pendingPairingAlert = .none
                        self.connection = nil
                        self.isConnected = false
                    } else {
                        self.connection = nil
                        self.isConnected = false
                    }
                case .browser:
                    // A stale handshake timeout from a connection we already abandoned while paused.
                    if self.migrationState == .paused { return }
                    if self.migrationState == .restoringConnection {
                        self.connectionRestorationAttempts += 1
                        if self.connectionRestorationAttempts > self.maxConnectionRestorationAttempts {
                            self.logger.log("migrationController.onAuthenticationFailed: exceeded maximum connection restoration attempts (\(self.maxConnectionRestorationAttempts)). Transitioning to interrupted state.", type: .error)
                            if self.isResumingFromPause {
                                self.failResumeAndReturnToPaused()
                                return
                            }
                            self.migrationState = .interrupted
                            MigrationReportController.shared.addError("Connection failed after \(self.maxConnectionRestorationAttempts) restoration attempts")
                        } else {
                            self.restoreConnection()
                        }
                    } else {
                        self.isConnected = false
                        self.migrationState = .wrongOTPCodeSent
                    }
                case .none:
                    break
                }
            }
        }).store(in: &cancellables)
        connection?.onIncomingPairingRequest.sink(receiveValue: { [weak self] hostname in
            Task { @MainActor in
                self?.handleIncomingPairingRequest(hostname: hostname, from: currentConnection)
            }
        }).store(in: &cancellables)
        connection?.onPairingRequestAccepted.sink(receiveValue: { [weak self] in
            Task { @MainActor in
                guard let self, self.connection === currentConnection else { return }
                self.isAwaitingPasscodeEntry = true
            }
        }).store(in: &cancellables)
        connection?.onPairingRequestDeclined.sink(receiveValue: { [weak self] in
            Task { @MainActor in
                guard let self, self.connection === currentConnection else { return }
                self.isAwaitingPasscodeEntry = false
                self.pairingRequestWasDeclined = true
            }
        }).store(in: &cancellables)
        connection?.onIncomingPairingRequestCancelled.sink(receiveValue: { [weak self] in
            Task { @MainActor in
                guard let self, self.connection === currentConnection else { return }
                self.pendingPairingAlert = .none
                self.connection = nil
                self.isConnected = false
            }
        }).store(in: &cancellables)
        connection?.onMigrationPaused.sink(receiveValue: { [weak self] in
            Task { @MainActor in
                guard let self, self.connection === currentConnection, self.operatingMode == .server else { return }
                self.handleMigrationPausedByPeer()
            }
        }).store(in: &cancellables)
    }

    // MARK: - Resource Management Methods

    /// Acquires a resource token for file operations
    func acquireConnectionOperationToken() async {
        logger.log("migrationController.acquireConnectionOperationToken: Asking for connection operation token...")
        await self.connectionOperationSemaphore.request()
    }
    
    /// Releases a resource token after file operations
    func releaseConnectionOperationToken() async {
        logger.log("migrationController.releaseConnectionOperationToken: releasing connection operation token...")
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
    
    /// Starts tracking the transfer progress: the ETA sampling timer and the connection-health watchdog.
    @MainActor
    func startProgressTracking() {
        guard connection?.connection != nil else {
            logger.log("migrationController.startProgressTracking: no connection available", type: .error)
            return
        }
        
        logger.log("migrationController.startProgressTracking: starting ETA sampling and connection-health watchdog", type: .default)
        migrationStartTime = Date()
        // The baseline is taken now, so time spent paused or reconnecting never counts as transfer time.
        lastETASample = (Date(), bytesSent, filesSent)
        etaSampleTimer?.invalidate()
        etaSampleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sampleETA()
            }
        }
        startConnectionHealthWatchdog()
    }

    /// Stops tracking the transfer progress: the ETA sampling timer and the connection-health watchdog.
    @MainActor
    func stopProgressTracking() {
        logger.log("migrationController.stopProgressTracking: stopping ETA sampling and connection-health watchdog", type: .default)
        etaSampleTimer?.invalidate()
        etaSampleTimer = nil
        lastETASample = nil
        migrationStartTime = nil
        stopConnectionHealthWatchdog()
    }

    // MARK: - Connection Health Watchdog

    /// Starts the connection-health watchdog: a fixed-cadence timer, independent of the ETA
    /// timer above, that samples throughput via its own `NWConnection.PendingDataTransferReport`
    /// window and triggers `attemptConnectionRepair(reason:)` if it sees no progress for
    /// `maxConsecutiveStalledWindows` consecutive samples while actively transmitting.
    @MainActor
    private func startConnectionHealthWatchdog() {
        consecutiveStalledWindows = 0
        isHealthCheckReportPending = false
        pendingHealthCheckReport = connection?.connection.startDataTransferReport()
        connectionHealthWatchdogTimer?.invalidate()
        connectionHealthWatchdogTimer = Timer.scheduledTimer(withTimeInterval: connectionHealthCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performConnectionHealthCheck()
            }
        }
    }

    /// Stops the connection-health watchdog and clears its state.
    @MainActor
    private func stopConnectionHealthWatchdog() {
        connectionHealthWatchdogTimer?.invalidate()
        connectionHealthWatchdogTimer = nil
        pendingHealthCheckReport = nil
        isHealthCheckReportPending = false
        consecutiveStalledWindows = 0
    }

    /// Whether the migration is in a state where bytes should actively be moving over the
    /// connection right now. While this is false (e.g. `.restoringConnection`, `.paused`), the
    /// watchdog resets its stalled-window count instead of counting - a connection drop already
    /// being handled by the existing restore logic must not also look like a fresh stall.
    private func isActivelyTransmitting() -> Bool {
        switch migrationState {
        case .fileMigration, .appMigration, .preferencesMigration, .completing:
            return true
        default:
            return false
        }
    }

    /// One watchdog tick. Collects the current health-check report window and starts a fresh one
    /// for the next tick; a report that never comes back by the next tick counts as stalled too.
    @MainActor
    private func performConnectionHealthCheck() {
        guard isActivelyTransmitting() else {
            consecutiveStalledWindows = 0
            isHealthCheckReportPending = false
            pendingHealthCheckReport = connection?.connection.startDataTransferReport()
            return
        }
        guard let report = pendingHealthCheckReport else {
            pendingHealthCheckReport = connection?.connection.startDataTransferReport()
            return
        }
        if isHealthCheckReportPending {
            logger.log("migrationController.performConnectionHealthCheck: previous report never returned, treating window as stalled", type: .error)
            registerStalledWindow()
            return
        }
        isHealthCheckReportPending = true
        report.collect(queue: .main) { [weak self] dataReport in
            Task { @MainActor in
                guard let self else { return }
                self.isHealthCheckReportPending = false
                self.pendingHealthCheckReport = self.connection?.connection.startDataTransferReport()
                guard self.isActivelyTransmitting() else {
                    self.consecutiveStalledWindows = 0
                    return
                }
                let sentBytes = dataReport.pathReports
                    .first(where: { self.connection?.connection.currentPath?.usesInterfaceType($0.interface.type) ?? false })?
                    .sentTransportByteCount ?? 0
                if sentBytes > 0 {
                    self.consecutiveStalledWindows = 0
                } else {
                    self.registerStalledWindow()
                }
            }
        }
    }

    /// Counts one stalled window and, once `maxConsecutiveStalledWindows` is reached, triggers repair.
    @MainActor
    private func registerStalledWindow() {
        consecutiveStalledWindows += 1
        guard consecutiveStalledWindows >= maxConsecutiveStalledWindows else { return }
        consecutiveStalledWindows = 0
        attemptConnectionRepair(reason: "no throughput for \(Int(connectionHealthCheckInterval) * maxConsecutiveStalledWindows)s")
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
    
    /// Samples the transfer progress and refreshes the estimate of the time left. Called once per
    /// second; only time spent actively transmitting is fed to the estimator.
    @MainActor
    private func sampleETA() {
        guard let migrationOption = migrationOption else {
            logger.log("migrationController.sampleETA: no migration option available", type: .error)
            return
        }
        let now = Date()
        let current = (date: now, bytes: bytesSent, files: filesSent)
        guard let previous = lastETASample else {
            lastETASample = current
            return
        }
        lastETASample = current

        // The baseline above is refreshed even when idle, so paused/reconnecting time is excluded.
        guard isActivelyTransmitting(), !isPausedForResources else { return }
        etaEstimator.record(deltaBytes: current.bytes - previous.bytes,
                            deltaFiles: current.files - previous.files,
                            activeSeconds: now.timeIntervalSince(previous.date))

        let rawEstimate = etaEstimator.estimate(remainingBytes: migrationOption.size - bytesSent,
                                                remainingFiles: migrationOption.numberOfFiles - filesSent)
        if let timeLeft = etaStabilizer.update(estimate: rawEstimate, at: now) {
            let newLabel = String(format: "migration.page.time.estimation.label".localized, timeLeft.prettyFormattedTimeLeft())
            if newLabel != estimatedTimeLeft {
                estimatedTimeLeft = newLabel
            }
        }
        if let bytesPerSecond = etaEstimator.smoothedBytesPerSecond, bytesPerSecond.isFinite {
            let newSpeed = "\(Int(bytesPerSecond / 1_000_000)) MB/s"
            if newSpeed != transferSpeed {
                transferSpeed = newSpeed
            }
        }

        etaSampleCount += 1
        if etaSampleCount % 30 == 0 {
            let sentSize = ByteCountFormatter.string(fromByteCount: Int64(bytesSent), countStyle: .file)
            let totalSize = ByteCountFormatter.string(fromByteCount: Int64(migrationOption.size), countStyle: .file)
            let remaining = rawEstimate?.prettyFormattedTimeLeft() ?? "calculating"
            logger.log("migrationController.sampleETA: progress — \(filesSent)/\(migrationOption.numberOfFiles) file(s), \(sentSize)/\(totalSize), \(transferSpeed), \(remaining) remaining", type: .default)
        }
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
        
        let incompatibleApps: [DiscoveredApplication]
        
        if destinationArch == .appleSilicon {
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
        var anyPreferenceSelected = false
        anyAppSelected = migrationOption.migrationAppList.reduce(anyAppSelected, { $0 || $1.isSelected })
        anyFileSelected = migrationOption.migrationFileList.reduce(anyFileSelected, { $0 || $1.isSelected })
        anyPreferenceSelected = migrationOption.migrationPreferencesList.reduce(anyPreferenceSelected, { $0 || $1.isSelected })
        guard anyAppSelected || anyFileSelected || anyPreferenceSelected else {
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

        migrationOption.discountDuplicatedSupportPaths()

        let totalFiles = migrationOption.migrationFileList.filter { $0.isSelected }.count
        let totalApps = migrationOption.migrationAppList.filter { $0.isSelected }.count
        let totalPreferences = migrationOption.migrationPreferencesList.filter { $0.isSelected }.count
        let totalSize = ByteCountFormatter.string(fromByteCount: Int64(migrationOption.size), countStyle: .file)
        logger.log("migrationController.startMigration: ===== starting migration \"\(migrationOption.name)\" — \(totalFiles) file(s), \(totalApps) app(s), \(totalPreferences) preference group(s), \(totalSize) total =====", type: .default)

        bytesSent = migrationOption.migrationFileList.reduce(1) { $0 + ($1.sent ? $1.fileSize : 0) }
        bytesSent = migrationOption.migrationAppList.reduce(bytesSent) { $0 + ($1.migratorFile.sent ? $1.migratorFile.fileSize : 0) }
        estimatedTimeLeft = String(format: "migration.page.time.estimation.label".localized, "migration.common.calculating.label".localized)
        etaEstimator = MigrationETAEstimator()
        etaStabilizer = ETADisplayStabilizer()
        etaSampleCount = 0

        MigrationReportController.shared.setMigrationSize(Int64(migrationOption.size))
        sleep(3)

        startProgressTracking()

        migrationTask = Task {
            do {
                try await self.sendMigrationSize(migrationOption.size)
            } catch {
                self.logger.log("migrationController.startMigration: delivery of migration size failed — error: \"\(error.localizedDescription)\"", type: .error)
            }

            if !migrationOption.migrationPreferencesList.contains(where: { $0.isSelected }) {
                do {
                    try await self.sendDefaults(DefaultsMessage(key: AppContext.skipRebootUserDefaultsKey, boolValue: true))
                } catch {
                    self.logger.log("migrationController.startMigration: delivery of default value failed — error: \"\(error.localizedDescription)\"", type: .error)
                }
            }

            self.logger.log("migrationController.startMigration: starting migration of \(totalFiles) file(s)", type: .default)
            await MainActor.run { self.migrationState = .fileMigration }

            for file in migrationOption.migrationFileList {
                guard !file.sent && file.isSelected else { continue }
                do {
                    self.logger.log("migrationController.startMigration: sending file \"\(file.url.fullURL().relativePath)\"")
                    try await self.sendFile(file)
                    self.logger.log("migrationController.startMigration: file sent \"\(file.url.fullURL().relativePath)\"")
                    file.sent = true
                    MigrationReportController.shared.addMigratedFile(file.url.fullURL().relativePath)
                } catch {
                    self.logger.log("migrationController.startMigration: failed to send file \"\(file.url.fullURL().relativePath)\" — error: \"\(error.localizedDescription)\"", type: .error)
                    MigrationReportController.shared.addError("migrationController.startMigration: failed to send file: \(file.url.fullURL().relativePath) - with error: \"\(error.localizedDescription)\"")
                }
            }

            self.logger.log("migrationController.startMigration: files migration complete", type: .default)
            self.logger.log("migrationController.startMigration: starting migration of \(totalApps) app(s)", type: .default)
            await MainActor.run { self.migrationState = .appMigration }

            let selectedAppsSupportPaths: [DiscoveredApplication: Set<URL>] = AppContext.shouldMigrateAppSupportFiles
                ? migrationOption.deduplicatedSupportPaths(forSelectedApps: migrationOption.migrationAppList.filter { $0.isSelected })
                : [:]

            for app in migrationOption.migrationAppList {
                guard !app.migratorFile.sent && app.isSelected else { continue }
                do {
                    self.logger.log("migrationController.startMigration: sending app \"\(app.migratorFile.url.fullURL().relativePath)\"")
                    try await self.sendFile(app.migratorFile)
                    self.logger.log("migrationController.startMigration: app sent \"\(app.migratorFile.url.fullURL().relativePath)\"")
                    app.migratorFile.sent = true

                    // Send app support files if enabled and discovered
                    if let supportPaths = selectedAppsSupportPaths[app], !supportPaths.isEmpty {
                        self.logger.log("migrationController.startMigration: sending \(supportPaths.count) support file(s) for \"\(app.name)\"")

                        for supportFilePath in supportPaths {
                            guard let supportFile = await MigratorFile.make(with: supportFilePath, ignoringURLExclusions: true) else {
                                self.logger.log("migrationController.startMigration: failed to create MigratorFile for support file \"\(supportFilePath.path)\"", type: .error)
                                MigrationReportController.shared.addError("Skipped support file (could not be scanned): \(supportFilePath.path)")
                                continue
                            }

                            do {
                                self.logger.log("migrationController.startMigration: sending support file \"\(supportFilePath.relativePath)\"")
                                try await self.sendFile(supportFile)
                                self.logger.log("migrationController.startMigration: support file sent \"\(supportFilePath.relativePath)\"")
                                supportFile.sent = true
                                MigrationReportController.shared.addMigratedFile(supportFilePath.relativePath)
                            } catch {
                                self.logger.log("migrationController.startMigration: failed to send support file \"\(supportFilePath.relativePath)\" — error: \"\(error.localizedDescription)\"", type: .error)
                                MigrationReportController.shared.addError("migrationController.startMigration: failed to send support file: \(supportFilePath.relativePath) - with error: \"\(error.localizedDescription)\"")
                            }
                        }

                        self.logger.log("migrationController.startMigration: completed sending support files for \"\(app.name)\"")
                    }
                } catch {
                    self.logger.log("migrationController.startMigration: failed to send app \"\(app.migratorFile.url.fullURL().relativePath)\" — error: \"\(error.localizedDescription)\"", type: .error)
                    MigrationReportController.shared.addError("migrationController.startMigration: failed to send file: \(app.migratorFile.url.fullURL().relativePath) - with error: \"\(error.localizedDescription)\"")
                }
            }

            self.logger.log("migrationController.startMigration: apps migration complete", type: .default)
            self.logger.log("migrationController.startMigration: starting migration of \(totalPreferences) preference group(s)", type: .default)
            await MainActor.run { self.migrationState = .preferencesMigration }

            for group in migrationOption.migrationPreferencesList {
                guard !group.sent && group.isSelected else { continue }
                do {
                    self.logger.log("migrationController.startMigration: sending preference group \"\(group.catalogID)\"")
                    try await self.sendPreferenceGroup(group)
                    group.sent = true
                    MigrationReportController.shared.addMigratedPreference(group.name)
                } catch {
                    self.logger.log("migrationController.startMigration: failed to send preference group \"\(group.catalogID)\" — error: \"\(error.localizedDescription)\"", type: .error)
                    MigrationReportController.shared.addError("migrationController.startMigration: failed to send preference group: \(group.catalogID) - with error: \"\(error.localizedDescription)\"")
                }
            }

            self.logger.log("migrationController.startMigration: preferences migration complete", type: .default)
            await MainActor.run { self.migrationState = .completing }

            // Verification and retry phase - ensure all selected items were migrated
            self.logger.log("migrationController.startMigration: starting verification phase", type: .default)
            let verificationResult = await self.verifyAndRetryMigration(migrationOption: migrationOption, maxRetries: 3)

            if !verificationResult.success {
                self.logger.log("migrationController.startMigration: verification failed — \(verificationResult.failedItems.count) item(s) could not be migrated", type: .error)
                for failedItem in verificationResult.failedItems {
                    MigrationReportController.shared.addError("Failed to migrate after retries: \(failedItem)")
                }
            } else {
                self.logger.log("migrationController.startMigration: verification complete — all items migrated successfully", type: .default)
            }

            let elapsedSeconds = Int(self.migrationStartTime.map { Date().timeIntervalSince($0) } ?? 0)
            self.logger.log("migrationController.startMigration: ===== migration \"\(migrationOption.name)\" finished in \(elapsedSeconds)s — \(self.filesSent) item(s) sent, \(verificationResult.failedItems.count) failed =====", type: .default)

            do {
                try await self.sendMigrationCompleted()
                MigrationReportController.shared.setMigrationEnd()
                await MainActor.run {
                    self.percentageCompleted = "100%"
                    self.estimatedTimeLeft = ""
                    self.migrationProgress = 1
                    self.stopProgressTracking()
                    NSSound(named: .init("Funk"))?.play()
                    Utils.Window.makeWindowFloating()
                }
            } catch {
                self.logger.log("migrationController.startMigration: send migration completion failed — error: \"\(error.localizedDescription)\"", type: .error)
            }
        }
    }
    // swiftlint:enable function_body_length

    /// Sends every domain of a preference group to the connected device.
    /// - Parameter group: The preference group to send.
    private func sendPreferenceGroup(_ group: PreferenceGroup) async throws {
        for (domain, data) in PreferencesDiscovery.payloads(for: group) {
            let message = PreferencesMessage(groupID: group.catalogID, applicationID: domain.applicationID, isByHost: domain.isByHost)
            try await self.sendPreferences(message, payload: data)
        }
    }

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
                logger.log("migrationController.verifyAndRetryMigration: found \(unsentFiles.count) unsent file(s)", type: .default)

                for file in unsentFiles {
                    let itemPath = file.url.fullURL().relativePath
                    let currentRetries = itemRetryCount[itemPath, default: 0]

                    if currentRetries >= maxRetries {
                        logger.log("migrationController.verifyAndRetryMigration: file \"\(itemPath)\" exceeded retry limit (\(currentRetries)/\(maxRetries))", type: .error)
                        if !failedItems.contains(itemPath) {
                            failedItems.append(itemPath)
                        }
                        continue
                    }

                    itemRetryCount[itemPath] = currentRetries + 1

                    do {
                        logger.log("migrationController.verifyAndRetryMigration: retrying file \"\(itemPath)\" (attempt \(currentRetries + 1)/\(maxRetries))")
                        try await MigrationController.shared.sendFile(file)
                        file.sent = true
                        MigrationReportController.shared.addMigratedFile(itemPath)
                        logger.log("migrationController.verifyAndRetryMigration: successfully sent file \"\(itemPath)\"")
                    } catch {
                        logger.log("migrationController.verifyAndRetryMigration: failed to send file \"\(itemPath)\" — error: \"\(error.localizedDescription)\"", type: .error)
                    }
                }
            }

            let unsentApps = migrationOption.migrationAppList.filter { !$0.migratorFile.sent && $0.isSelected }
            if !unsentApps.isEmpty {
                hasUnsentItems = true
                logger.log("migrationController.verifyAndRetryMigration: found \(unsentApps.count) unsent app(s)", type: .default)

                for app in unsentApps {
                    let itemPath = app.url.relativePath
                    let currentRetries = itemRetryCount[itemPath, default: 0]

                    if currentRetries >= maxRetries {
                        logger.log("migrationController.verifyAndRetryMigration: app \"\(itemPath)\" exceeded retry limit (\(currentRetries)/\(maxRetries))", type: .error)
                        if !failedItems.contains(itemPath) {
                            failedItems.append(itemPath)
                        }
                        continue
                    }

                    itemRetryCount[itemPath] = currentRetries + 1

                    do {
                        logger.log("migrationController.verifyAndRetryMigration: retrying app \"\(itemPath)\" (attempt \(currentRetries + 1)/\(maxRetries))")
                        try await MigrationController.shared.sendFile(app.migratorFile)
                        app.migratorFile.sent = true
                        logger.log("migrationController.verifyAndRetryMigration: successfully sent app \"\(itemPath)\"")
                    } catch {
                        logger.log("migrationController.verifyAndRetryMigration: failed to send app \"\(itemPath)\" — error: \"\(error.localizedDescription)\"", type: .error)
                    }
                }
            }

            let unsentPreferences = migrationOption.migrationPreferencesList.filter { !$0.sent && $0.isSelected }
            if !unsentPreferences.isEmpty {
                hasUnsentItems = true
                logger.log("migrationController.verifyAndRetryMigration: found \(unsentPreferences.count) unsent preference group(s)", type: .default)

                for group in unsentPreferences {
                    let itemPath = group.catalogID
                    let currentRetries = itemRetryCount[itemPath, default: 0]

                    if currentRetries >= maxRetries {
                        logger.log("migrationController.verifyAndRetryMigration: preference group \"\(itemPath)\" exceeded retry limit (\(currentRetries)/\(maxRetries))", type: .error)
                        if !failedItems.contains(itemPath) {
                            failedItems.append(itemPath)
                        }
                        continue
                    }

                    itemRetryCount[itemPath] = currentRetries + 1

                    do {
                        logger.log("migrationController.verifyAndRetryMigration: retrying preference group \"\(itemPath)\" (attempt \(currentRetries + 1)/\(maxRetries))")
                        try await MigrationController.shared.sendPreferenceGroup(group)
                        group.sent = true
                        MigrationReportController.shared.addMigratedPreference(group.name)
                        logger.log("migrationController.verifyAndRetryMigration: successfully sent preference group \"\(itemPath)\"")
                    } catch {
                        logger.log("migrationController.verifyAndRetryMigration: failed to send preference group \"\(itemPath)\" — error: \"\(error.localizedDescription)\"", type: .error)
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
        let finalUnsentPreferences = migrationOption.migrationPreferencesList.filter { !$0.sent && $0.isSelected }

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

        for group in finalUnsentPreferences {
            let itemPath = group.catalogID
            if !failedItems.contains(itemPath) {
                failedItems.append(itemPath)
            }
        }

        let success = failedItems.isEmpty
        logger.log("migrationController.verifyAndRetryMigration: verification complete — success: \(success), failed item(s): \(failedItems.count)", type: success ? .default : .error)
        
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

    /// Sends one preferences domain through the current active connection
    /// - Parameters:
    ///   - object: Identifies the domain and the `PreferenceGroup` it belongs to.
    ///   - payload: The binary property list of the domain's values.
    func sendPreferences(_ object: PreferencesMessage, payload: Data) async throws {
        guard let currentConnection = connection else {
            logger.log("migrationController.sendPreferences: no active connection", type: .error)
            throw NSError(domain: "MigrationController", code: 2001,
                         userInfo: [NSLocalizedDescriptionKey: "No active connection"])
        }
        try await currentConnection.sendPreferences(object, payload: payload)
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
    
    // MARK: - Pause / Resume

    /// Start time of the migration at the moment it was paused, restored on resume so the
    /// elapsed-time log stays accurate across the pause.
    private var migrationStartTimeBeforePause: Date?

    /// Source only: pauses the migration so the devices can be disconnected. The migration task
    /// is suspended, not cancelled: every send parks in `awaitConnectionReadiness()` while the
    /// state is `.paused`, and carries on from the same chunk after `resumeMigration()`.
    @MainActor
    func pauseMigration() async {
        guard operatingMode == .browser, isActivelyTransmitting(), !isPausing else { return }
        logger.log("migrationController.pauseMigration: pausing migration", type: .default)
        isPausing = true
        // From here `sendAsyncWrapper` starts no new send.
        migrationState = .paused

        // Let the sends already handed to Network.framework finish so the connection is closed
        // on a message boundary. On timeout we pause anyway: chunks carry their byte offset, so
        // a chunk re-sent after resume overwrites itself.
        let deadline = Date().addingTimeInterval(pauseQuiesceTimeout)
        while (connection?.inFlightSendCount ?? 0) > 0 && Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        migrationStartTimeBeforePause = migrationStartTime
        stopProgressTracking()
        do {
            try await connection?.sendMigrationPaused()
        } catch {
            logger.log("migrationController.pauseMigration: failed to notify the destination -> \"\(error.localizedDescription)\"", type: .error)
        }
        connection?.closeForPause()
        isConnected = false
        connectedDeviceIsReady = false
        isPausing = false
    }

    /// Source only: reconnects to the destination of a paused migration and lets the suspended
    /// migration task continue.
    @MainActor
    func resumeMigration() {
        guard migrationState == .paused, operatingMode == .browser, !isResumingFromPause else { return }
        logger.log("migrationController.resumeMigration: resuming migration", type: .default)
        resumeFailed = false
        isResumingFromPause = true
        connectionRestorationAttempts = 0
        migrationState = .restoringConnection
        restoreConnection()

        resumeTimeoutTask?.cancel()
        resumeTimeoutTask = Task { @MainActor [weak self] in
            guard let timeout = self?.resumeTimeout else { return }
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled, let self, self.isResumingFromPause else { return }
            self.logger.log("migrationController.resumeMigration: timed out waiting for the destination", type: .error)
            self.failResumeAndReturnToPaused()
        }
    }

    /// Source only: the reconnect after a pause worked; restarts the progress/health timers.
    @MainActor
    private func completeResume() {
        logger.log("migrationController.completeResume: reconnected, resuming transfer", type: .default)
        resumeTimeoutTask?.cancel()
        resumeTimeoutTask = nil
        isResumingFromPause = false
        resumeFailed = false
        startProgressTracking()
        if let start = migrationStartTimeBeforePause {
            migrationStartTime = start
        }
        migrationStartTimeBeforePause = nil
    }

    /// Source only: the destination couldn't be reached, so go back to the paused screen and
    /// let the human try again.
    @MainActor
    private func failResumeAndReturnToPaused() {
        logger.log("migrationController.failResumeAndReturnToPaused: couldn't reach the destination, staying paused", type: .error)
        resumeTimeoutTask?.cancel()
        resumeTimeoutTask = nil
        isResumingFromPause = false
        connection?.connection.forceCancel()
        isConnected = false
        connectedDeviceIsReady = false
        connectionRestorationAttempts = 0
        resumeFailed = true
        migrationState = .paused
    }

    /// Destination only: the source paused and is closing the connection. Keeps the migration
    /// state and listens again so the source's reconnect is auto-accepted (see `startServer`).
    @MainActor
    private func handleMigrationPausedByPeer() {
        logger.log("migrationController.handleMigrationPausedByPeer: source paused the migration", type: .default)
        migrationState = .paused
        isConnected = false
        connectedDeviceIsReady = false
        startServer(withPasscode: passcode)
    }
}
// swiftlint:enable type_body_length file_length large_tuple
