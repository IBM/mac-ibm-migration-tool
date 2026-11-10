//
//  NetworkConnection.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 15/11/2023.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//
//  swiftlint:disable function_body_length type_body_length file_length

import Foundation
import Network
import Combine

/// Represents and manages a network connection, handling both incoming and outgoing data transfer.
@MainActor
final class NetworkConnection {

    // MARK: - Constants
    
    /// Subject for publishing hostname changes of the connected device.
    let onHostNameChange = PassthroughSubject<String, Never>()
    /// Subject for publishing available space changes on the connected device.
    let onAvailableSpaceChange = PassthroughSubject<Int, Never>()
    /// Subject for publishing availability of the connected device to receive data.
    let onReadyToReceive = PassthroughSubject<Bool, Never>()
    /// Subject for publishing the receive of the migration metadata from the source device.
    let onMigrationMetadataReceived = PassthroughSubject<Int, Never>()
    /// Subject for publishing size of bytes received from file migration.
    let onBytesReceived = PassthroughSubject<Int, Never>()
    /// Subject for publishing size of bytes sent during file migration.
    let onBytesSent = PassthroughSubject<Int, Never>()
    /// Subject for publishing the completion of the migration.
    let onMigrationCompleted = PassthroughSubject<Bool, Never>()
    /// Subject for publishing new connection states.
    let onNewConnectionState = PassthroughSubject<NWConnection.State, Never>()
    /// Subject for publishing when a file have been sent.
    let onFileSent = PassthroughSubject<Int, Never>()
    /// Subject for publishing device info received from the connected device.
    let onDeviceInfoReceived = PassthroughSubject<DeviceInfoMessage, Never>()
    /// Subject for publishing a failed application-layer pairing handshake (e.g. wrong code,
    /// or a channel-binding mismatch from a relay attempt). The connection is cancelled
    /// immediately after this fires.
    let onAuthenticationFailed = PassthroughSubject<PairingFailureReason, Never>()
    /// Distinguishes why a pairing handshake failed, so callers can tell an actual wrong-code
    /// guess (the only thing that should count toward a lockout) apart from a decline, a
    /// cancel, or a timeout before any code was even checked.
    enum PairingFailureReason: Equatable {
        case wrongCode
        case other
    }
    /// Server only: fires with the peer's hostname as soon as its `pairingRequest` arrives,
    /// before any passcode-based crypto runs. The UI must call `acceptIncomingPairingRequest()`
    /// or `declineIncomingPairingRequest()` in response.
    let onIncomingPairingRequest = PassthroughSubject<String, Never>()
    /// Client only: fires once the destination has accepted this device's `pairingRequest`,
    /// so the UI should unlock the code entry field. Sent for both a human-driven accept and
    /// an auto-accepted same-host retry - purely so the client knows when it may proceed; it
    /// carries no other information and doesn't change anything about the handshake itself.
    let onPairingRequestAccepted = PassthroughSubject<Void, Never>()
    /// Client only: fires if the destination explicitly declined this device's
    /// `pairingRequest`, or never responded before `pendingRequestTimeout` elapsed. Distinct
    /// from `onAuthenticationFailed`, since no passcode has been entered yet at this point.
    let onPairingRequestDeclined = PassthroughSubject<Void, Never>()
    /// Server only: fires if the source human cancelled the connection attempt before it
    /// completed - either while their pending request is showing, or while they were still
    /// entering the code. Distinct from `onAuthenticationFailed`, so a deliberate cancel never
    /// counts toward the wrong-code lockout.
    let onIncomingPairingRequestCancelled = PassthroughSubject<Void, Never>()
    /// Destination only: fires when the source tells us it paused the migration and is about
    /// to close the connection.
    let onMigrationPaused = PassthroughSubject<Void, Never>()

    // MARK: - Private Constants

    /// Logger instance.
    nonisolated private let logger = MLogger.main.scoped(to: .network)
    /// How long to wait for the application-layer pairing handshake to complete after the TLS
    /// connection becomes ready, before treating it as failed.
    private let handshakeTimeout: TimeInterval = 15
    /// How long an incoming `pairingRequest` may sit unanswered - waiting for the peer to send
    /// it at all, or waiting for the destination human to accept/decline it - before it's
    /// treated as declined.
    private let pendingRequestTimeout: TimeInterval = 90
    /// The build identity mixed into the pairing handshake so only matching builds can pair.
    /// Fixed in DEBUG builds so different debug builds of the app can still pair with each other.
    private var pairingBuildIdentity: String {
#if DEBUG
        return "MigrationController-Debug"
#else
        return PairingBuildIdentity.value
#endif
    }

    // MARK: - Private Variables

    /// Stores the endpoint for outgoing connections to enable reconnection
    private var endpoint: NWEndpoint?
    /// Stores the passcode for reconnection
    private var passcode: String?
    /// Indicates if this is an incoming or outgoing connection
    private var isIncomingConnection: Bool = false
    /// Whether the application-layer pairing handshake has completed successfully. Network
    /// framework's `.ready` state only means the TLS 1.3 handshake succeeded; since TLS 1.3
    /// dropped external-PSK support, the pairing code is verified afterwards at this layer, and
    /// `onNewConnectionState` isn't told about `.ready` until this becomes `true`.
    private(set) var isAuthenticated: Bool = false
    /// Runs the CPace-style PAKE exchange that checks the pairing code once TLS is ready.
    private var pairingAuthenticator: PairingAuthenticator?
    /// The TLS 1.3 exporter secret for the current connection, binding the pairing exchange to
    /// this exact TLS session so a relaying man-in-the-middle can't complete it.
    private var channelBinding: Data?
    /// Fires `onAuthenticationFailed` if the pairing handshake hasn't finished within `handshakeTimeout`.
    private var handshakeTimeoutWorkItem: DispatchWorkItem?
    /// Server only: the peer's hostname from its `pairingRequest`, once received and until the
    /// destination human accepts or declines it.
    private var pendingRequestHostname: String?
    /// Fires a decline if a pending `pairingRequest` (or the wait for one) isn't resolved
    /// within `pendingRequestTimeout`.
    private var pendingRequestTimeoutWorkItem: DispatchWorkItem?
    /// Server only: whether the destination human has accepted the pending pairing request.
    /// Gates `handleAuthHello`, so a client can't skip the approval step by sending its
    /// `authHello` before anyone agreed to it.
    private var isPairingAccepted: Bool = false
    /// Server only: whether this connection has ever received the peer's `pairingRequest`.
    /// Lets `MigrationController` tell which of two simultaneous incoming connections (the
    /// source racing IPv6 and IPv4) is the one the source actually kept.
    private(set) var hasReceivedPairingRequest: Bool = false

    // MARK: - Pause Support

    /// Number of `connection.send` calls handed to Network.framework whose completion hasn't
    /// fired yet. `MigrationController.pauseMigration()` waits for this to reach zero so the
    /// connection is only closed on a message boundary.
    private(set) var inFlightSendCount: Int = 0
    
    // MARK: - Variables
    
    /// The actual network connection being managed.
    private(set) var connection: NWConnection
    
    /// Stores the hostname of the connected device and publishes changes to subscribers.
    var connectedDeviceHostName: String = "" {
        didSet {
            self.onHostNameChange.send(connectedDeviceHostName)
        }
    }
    /// Stores the available space on the connected device and publishes changes to subscribers.
    var connectedDeviceAvailableSpace: Int = -1 {
        didSet {
            self.onAvailableSpaceChange.send(connectedDeviceAvailableSpace)
        }
    }
    /// Stores the size of the migration in bytes.
    var migrationSizeInBytes: Int = 0 {
        didSet {
            self.onMigrationMetadataReceived.send(migrationSizeInBytes)
        }
    }
    var isMigrationCompleted: Bool = false {
        didSet {
            self.onMigrationCompleted.send(isMigrationCompleted)
            if isMigrationCompleted {
                self.connection.cancel()
            }
        }
    }
    /// Stores symbolic link messages that need to be sent to the connected device.
    var symlinks: [SymbolicLinkMessage] = []
    /// Provides the current state of the network connection.
    var state: NWConnection.State {
        return connection.state
    }
    var currentInterfaceType: NWInterface.InterfaceType? {
        guard let currentPath = connection.currentPath else { return nil }
        guard let currentInterface = currentPath.availableInterfaces.first(where: { currentPath.usesInterfaceType($0.type) }) else { return nil }
        return currentInterface.type
    }
    /// Server only: the remote peer's IP address, ignoring its ephemeral port (which differs on
    /// every connection attempt from the same machine). Used to recognize a wrong-code retry
    /// from the same device, so it can be auto-accepted without re-prompting.
    var remoteHost: NWEndpoint.Host? {
        guard case .hostPort(let host, _) = connection.endpoint else { return nil }
        return host
    }
    
    // MARK: - Intializers
    
    /// Initializes a new network connection for outgoing connections. The passcode isn't known
    /// yet: the client identifies itself by hostname first (see `beginPairingHandshake`), and
    /// the passcode is supplied later via `submitPasscode` once the destination approves it -
    /// except on a `restoreConnection()` reconnect, which reuses the passcode already submitted
    /// for the original pairing.
    /// - Parameter endpoint: The network endpoint to connect to.
    init(endpoint: NWEndpoint) {
        logger.log("networkConnection.initOutgoingConnection: endpoint \"\(endpoint.debugDescription)\"", type: .default)

        // Store connection parameters for potential reconnection
        self.endpoint = endpoint
        self.isIncomingConnection = false

        let parameters = NWParameters(tlsIdentity: nil)
        connection = NWConnection(to: endpoint, using: parameters)
        setupConnectionHandlers()
    }

    /// Initializes a new network connection for handling incoming connections.
    /// - Parameters:
    ///   - connection: The incoming network connection.
    ///   - passcode: The passcode this server is advertising, checked against the client's
    ///     pairing handshake once the connection reaches TLS-ready.
    init(connection: NWConnection, withPasscode passcode: String) {
        logger.log("networkConnection.initIncomingConnection: connection \"\(connection.debugDescription)\"", type: .default)
        self.connection = connection
        self.passcode = passcode
        self.isIncomingConnection = true
        setupConnectionHandlers()
        connection.start(queue: .main)
    }
    
    // MARK: - Connection Management Methods
    
    /// Sets up all connection handlers (path, state, viability updates)
    private func setupConnectionHandlers() {
        connection.pathUpdateHandler = { path in
            self.logger.log("networkConnection.pathUpdateHandler: newPath \"\(path.debugDescription)\"")
        }
        connection.betterPathUpdateHandler = { betterPathAvailable in
            self.logger.log("networkConnection.betterPathUpdateHandler: betterPathAvailable \"\(betterPathAvailable.description)\"")
        }
        connection.viabilityUpdateHandler = { available in
            self.logger.log("networkConnection.viabilityUpdateHandler: isAvailable \"\(available.description)\"")
        }
        // `NWConnection`'s handlers aren't `@MainActor`-annotated, but `connection.start(queue: .main)`
        // guarantees they always fire on the main queue.
        connection.stateUpdateHandler = { newState in
            MainActor.assumeIsolated {
                let role = self.isIncomingConnection ? "incoming" : "outgoing"
                self.logger.log("networkConnection.stateUpdateHandler: \(role) connection state: \"\(String(describing: newState))\"")
                switch newState {
                case .ready:
                    if let metadata = self.connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata {
                        let version = sec_protocol_metadata_get_negotiated_tls_protocol_version(metadata.securityProtocolMetadata)
                        let suite   = sec_protocol_metadata_get_negotiated_tls_ciphersuite(metadata.securityProtocolMetadata)
                        self.logger.log("networkConnection.stateUpdateHandler: negotiated TLS version: \(version), suite: \(suite)")
                    }
                    self.logger.log("networkConnection.stateUpdateHandler: \(role) connection established", type: .default)
                    self.receiveNextMessage()
                    self.beginPairingHandshake()
                case .failed(let error):
                    self.logger.log("networkConnection.stateUpdateHandler: \(role) connection failed — error: \"\(error.localizedDescription)\"", type: .error)
                    self.onNewConnectionState.send(newState)
                case .cancelled:
                    self.logger.log("networkConnection.stateUpdateHandler: \(role) connection cancelled", type: .default)
                    self.onNewConnectionState.send(newState)
                default:
                    self.onNewConnectionState.send(newState)
                }
            }
        }
    }

    /// Kicks off the pairing handshake once the TLS 1.3 connection is ready: exports the
    /// channel binding, then either waits for the peer to identify itself (server), or sends
    /// this device's `pairingRequest` (client). Always sent, even on a `restoreConnection()`
    /// reconnect where the passcode is already known - the server's fresh `NetworkConnection`
    /// for the new incoming TCP connection has never seen this device and won't accept an
    /// `authHello` without a `pairingRequest` to auto-accept first (see `handlePairingDecision`,
    /// which submits the already-known passcode automatically once that accept arrives).
    private func beginPairingHandshake() {
        guard let channelBinding = exportChannelBinding() else {
            logger.log("networkConnection.beginPairingHandshake: failed to export TLS channel binding", type: .error)
            failAuthentication()
            return
        }
        self.channelBinding = channelBinding

        if isIncomingConnection {
            startPendingRequestTimeout()
            return
        }

        startPendingRequestTimeout()
        Task {
            do {
                let hostname = Host.current().localizedName ?? "Connected Device"
                try await sendAuthMessage(.pairingRequest, PairingMessage(protocolVersion: PairingMessage.currentProtocolVersion, hostname: hostname))
            } catch {
                logger.log("networkConnection.beginPairingHandshake: failed to send pairingRequest -> \"\(error.localizedDescription)\"", type: .error)
                failAuthentication()
            }
        }
    }

    /// Called once the destination has accepted this device's `pairingRequest` and the human
    /// has typed in the code relayed from the destination's screen. This is exactly what
    /// `beginPairingHandshake()` used to do immediately at TLS-ready, before the pre-auth
    /// hostname/approval step existed.
    func submitPasscode(_ passcode: String) async {
        self.passcode = passcode
        guard let channelBinding else {
            logger.log("networkConnection.submitPasscode: missing channel binding", type: .error)
            failAuthentication()
            return
        }
        await sendAuthHello(passcode: passcode, channelBinding: channelBinding)
    }

    /// Builds this device's `PairingAuthenticator`, sends `authHello`, and starts the crypto
    /// handshake timeout. Shared by a fresh pairing's `submitPasscode` and a restore's
    /// `beginPairingHandshake`, once the passcode is known.
    private func sendAuthHello(passcode: String, channelBinding: Data) async {
        startHandshakeTimeout()

        do {
            var authenticator = try PairingAuthenticator(role: .client, passcode: passcode,
                                                           channelBinding: channelBinding, context: pairingBuildIdentity)
            let share = try authenticator.makeShare()
            pairingAuthenticator = authenticator
            try await sendAuthMessage(.authHello, PairingMessage(protocolVersion: PairingMessage.currentProtocolVersion, share: share))
        } catch {
            logger.log("networkConnection.sendAuthHello: failed to send authHello -> \"\(error.localizedDescription)\"", type: .error)
            failAuthentication()
        }
    }

    /// Starts (or restarts) the timer bounding how long an incoming `pairingRequest` may sit
    /// unanswered before being treated as declined - used while waiting for the peer to send
    /// it at all, while waiting for the destination human's decision once it arrives, and
    /// (restarted) while waiting for `authHello` after that human accepts.
    private func startPendingRequestTimeout() {
        pendingRequestTimeoutWorkItem?.cancel()
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isAuthenticated else { return }
            self.logger.log("networkConnection.startPendingRequestTimeout: pending pairing request timed out", type: .error)
            if self.isIncomingConnection {
                if self.isPairingAccepted {
                    self.cancelAcceptedPairingRequest()
                } else {
                    self.declineIncomingPairingRequest()
                }
            } else {
                self.onPairingRequestDeclined.send()
                self.failAuthentication()
            }
        }
        pendingRequestTimeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + pendingRequestTimeout, execute: timeoutWorkItem)
    }

    /// Server: the destination human approved the pending `pairingRequest` (or a same-host
    /// retry was auto-accepted). Tells the client only that it may now proceed - not the code,
    /// not anything else - so its code entry field can unlock; the human still has to relay
    /// the code themselves. Restarts the pending-request timer to bound how long to wait for
    /// that code's `authHello`.
    func acceptIncomingPairingRequest() {
        guard isIncomingConnection, pendingRequestHostname != nil else { return }
        logger.log("networkConnection.acceptIncomingPairingRequest: pairing request accepted, waiting for passcode confirmation", type: .default)
        pendingRequestHostname = nil
        isPairingAccepted = true
        Task {
            try? await sendAuthMessage(.pairingDecision, PairingMessage(protocolVersion: PairingMessage.currentProtocolVersion, accepted: true))
        }
        startPendingRequestTimeout()
    }

    /// Starts (or restarts) the crypto handshake timeout, on the client right after sending
    /// `authHello`, and on the server right after validating it - now waiting for the rest of
    /// the (fast, machine-paced) exchange to complete.
    private func startHandshakeTimeout() {
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isAuthenticated else { return }
            self.logger.log("networkConnection.startHandshakeTimeout: handshake timed out", type: .error)
            self.failAuthentication(reason: self.isIncomingConnection ? .wrongCode : .other)
        }
        handshakeTimeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + handshakeTimeout, execute: timeoutWorkItem)
    }

    /// Server: the destination human declined the pending `pairingRequest` (or none ever
    /// arrived and `pendingRequestTimeout` elapsed). Tells the client, if there was anything to
    /// tell it about, then cancels so the listener can accept a fresh attempt.
    func declineIncomingPairingRequest() {
        guard isIncomingConnection else { return }
        pendingRequestTimeoutWorkItem?.cancel()
        pendingRequestTimeoutWorkItem = nil
        let hadPendingRequest = pendingRequestHostname != nil
        pendingRequestHostname = nil
        logger.log("networkConnection.declineIncomingPairingRequest: declining pairing request (had pending request: \(hadPendingRequest))", type: .default)
        guard hadPendingRequest else {
            failAuthentication()
            return
        }
        Task {
            try? await sendAuthMessage(.pairingDecision, PairingMessage(protocolVersion: PairingMessage.currentProtocolVersion, accepted: false))
            failAuthentication()
        }
    }

    /// Server: the destination human cancelled after already accepting (the code-showing
    /// alert's Cancel button, or the pending-request timeout elapsing while waiting for
    /// `authHello`). Tells the client so it doesn't sit on a code entry that will never
    /// succeed, then resets for a fresh attempt.
    func cancelAcceptedPairingRequest() {
        guard isIncomingConnection, isPairingAccepted else { return }
        logger.log("networkConnection.cancelAcceptedPairingRequest: destination cancelled an already-accepted pairing request", type: .default)
        isPairingAccepted = false
        pendingRequestTimeoutWorkItem?.cancel()
        pendingRequestTimeoutWorkItem = nil
        Task {
            try? await sendAuthMessage(.pairingDecision, PairingMessage(protocolVersion: PairingMessage.currentProtocolVersion, accepted: false))
            failAuthentication()
        }
    }

    /// Client: the human cancelled the connection attempt before it completed - either while
    /// waiting for the destination's decision, or while still entering the code. Best-effort
    /// informs the destination so it can dismiss its prompt, then tears the connection down
    /// directly, deliberately bypassing `failAuthentication()`/`onAuthenticationFailed` so a
    /// cancel is never mistaken for a wrong code or counted toward any lockout.
    func cancelPairingRequest() {
        guard !isIncomingConnection, !isAuthenticated else { return }
        logger.log("networkConnection.cancelPairingRequest: source cancelled the pairing request", type: .default)
        pendingRequestTimeoutWorkItem?.cancel()
        pendingRequestTimeoutWorkItem = nil
        handshakeTimeoutWorkItem?.cancel()
        handshakeTimeoutWorkItem = nil
        Task {
            try? await sendAuthMessage(.pairingCancelled, PairingMessage(protocolVersion: PairingMessage.currentProtocolVersion))
            connection.cancel()
        }
    }

    /// Exports the TLS 1.3 exporter secret used to bind the pairing exchange to this exact
    /// TLS session, so a man-in-the-middle terminating its own TLS session with each side
    /// (and so seeing a different exporter value on each side) can't relay pairing messages
    /// between them.
    private func exportChannelBinding() -> Data? {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else {
            return nil
        }
        let label = "EXPORTER-DataShift-Pairing"
        let secret: dispatch_data_t? = label.withCString { labelPointer in
            sec_protocol_metadata_create_secret(metadata.securityProtocolMetadata, label.utf8.count, labelPointer, 32)
        }
        guard let secret else { return nil }
        return Data(secret as DispatchData)
    }

    /// Marks the pairing handshake as successfully completed: cancels the handshake timeout,
    /// forwards `.ready` to `onNewConnectionState` (this is the point at which the rest of the
    /// app first learns the connection is usable), and kicks off the existing post-ready
    /// handshake (hostname/free-space and device-info exchange).
    private func onAuthenticationSucceeded() {
        logger.log("networkConnection.onAuthenticationSucceeded: pairing handshake succeeded, connection authenticated", type: .default)
        handshakeTimeoutWorkItem?.cancel()
        handshakeTimeoutWorkItem = nil
        isAuthenticated = true
        pairingAuthenticator = nil

        if let interfaceTypeString = currentInterfaceType?.stringValue, !isIncomingConnection {
            MigrationReportController.shared.setMigrationTransferMethod(interfaceTypeString)
        }
        onNewConnectionState.send(.ready)

        if !isIncomingConnection {
            Task {
                try? await self.sendHostName()
                try? await self.sendDeviceInfo()
            }
        } else {
            Task {
                try? await self.sendAvailableFreeSpace()
                try? await self.sendDeviceInfo()
            }
        }
    }

    /// Marks the pairing handshake as failed: cancels the handshake timeout, publishes
    /// `onAuthenticationFailed`, and cancels the underlying connection so a fresh attempt
    /// (server) or restoration (client) can start clean.
    private func failAuthentication(reason: PairingFailureReason = .other) {
        guard !isAuthenticated else { return }
        logger.log("networkConnection.failAuthentication: pairing handshake failed (reason: \(reason)), cancelling connection", type: .default)
        handshakeTimeoutWorkItem?.cancel()
        handshakeTimeoutWorkItem = nil
        pendingRequestTimeoutWorkItem?.cancel()
        pendingRequestTimeoutWorkItem = nil
        pendingRequestHostname = nil
        isPairingAccepted = false
        pairingAuthenticator = nil
        onAuthenticationFailed.send(reason)
        connection.cancel()
    }

    // MARK: - Pairing Handshake Messages

    /// Server: the client's hostname, sent before either side touches the passcode. Surfaces
    /// it to the UI (or, on a mid-migration reconnect, auto-accepts without re-prompting the
    /// human who already approved this device once).
    private func handlePairingRequest(_ message: PairingMessage) throws {
        guard isIncomingConnection, let hostname = message.hostname else {
            throw PairingAuthenticator.PairingError.protocolViolation
        }
        logger.log("networkConnection.handlePairingRequest: incoming pairing request from \"\(hostname)\"", type: .default)
        hasReceivedPairingRequest = true
        pendingRequestHostname = hostname
        startPendingRequestTimeout()
        onIncomingPairingRequest.send(hostname)
    }

    /// Server: the source human aborted the connection attempt. Dismisses any pending request
    /// UI and resets so the listener can accept a fresh attempt, without touching the
    /// wrong-code lockout - a deliberate cancel isn't a failed guess.
    private func handlePairingCancelled(_ message: PairingMessage) throws {
        guard isIncomingConnection else {
            throw PairingAuthenticator.PairingError.protocolViolation
        }
        logger.log("networkConnection.handlePairingCancelled: pairing request cancelled by the source device", type: .default)
        pendingRequestTimeoutWorkItem?.cancel()
        pendingRequestTimeoutWorkItem = nil
        pendingRequestHostname = nil
        isPairingAccepted = false
        onIncomingPairingRequestCancelled.send()
        connection.cancel()
    }

    /// Client: the destination's accept/decline of this device's `pairingRequest`. On a fresh
    /// pairing (no `passcode` yet) accept unlocks the code entry field (see
    /// `onPairingRequestAccepted`); on a `restoreConnection()` reconnect the passcode from the
    /// original pairing is already known, so it's submitted immediately instead of surfacing
    /// `onPairingRequestAccepted` and leaving the UI waiting on a human who already entered it
    /// once. Decline covers both the first alert's decline and a cancel after already accepting.
    private func handlePairingDecision(_ message: PairingMessage) throws {
        guard !isIncomingConnection, let accepted = message.accepted else {
            throw PairingAuthenticator.PairingError.protocolViolation
        }
        pendingRequestTimeoutWorkItem?.cancel()
        pendingRequestTimeoutWorkItem = nil
        guard accepted else {
            logger.log("networkConnection.handlePairingDecision: pairing request declined by the destination device", type: .default)
            onPairingRequestDeclined.send()
            pairingAuthenticator = nil
            connection.cancel()
            return
        }
        logger.log("networkConnection.handlePairingDecision: pairing request accepted by the destination device", type: .default)
        if let passcode, let channelBinding {
            Task { await sendAuthHello(passcode: passcode, channelBinding: channelBinding) }
        } else {
            onPairingRequestAccepted.send()
        }
    }

    /// Server: the client's first message. Derives the shared key from the client's share and
    /// replies with the server's own share plus a confirmation MAC. Only valid once the
    /// destination human has accepted the pairing request - this is what actually stops a
    /// client from skipping that approval step.
    private func handleAuthHello(_ message: PairingMessage) async throws {
        guard isIncomingConnection, isPairingAccepted, let passcode, let channelBinding,
              message.protocolVersion == PairingMessage.currentProtocolVersion,
              let clientShare = message.share else {
            throw PairingAuthenticator.PairingError.protocolViolation
        }
        var authenticator = try PairingAuthenticator(role: .server, passcode: passcode,
                                                       channelBinding: channelBinding, context: pairingBuildIdentity)
        let myShare = try authenticator.makeShare()
        try authenticator.deriveKeys(peerShare: clientShare)
        let confirmation = try authenticator.confirmation()
        pairingAuthenticator = authenticator
        startHandshakeTimeout()

        try await sendAuthMessage(.authResponse, PairingMessage(protocolVersion: PairingMessage.currentProtocolVersion,
                                                                  share: myShare, confirmation: confirmation))
    }

    /// Client: the server's response. Derives the shared key, verifies the server's confirmation
    /// (this is where a wrong passcode or a relayed/MITM'd channel binding first surfaces), and
    /// replies with the client's own confirmation MAC.
    private func handleAuthResponse(_ message: PairingMessage) async throws {
        guard !isIncomingConnection, var authenticator = pairingAuthenticator,
              message.protocolVersion == PairingMessage.currentProtocolVersion,
              let serverShare = message.share, let serverConfirmation = message.confirmation else {
            throw PairingAuthenticator.PairingError.protocolViolation
        }
        try authenticator.deriveKeys(peerShare: serverShare)
        try authenticator.verify(peerConfirmation: serverConfirmation)
        let confirmation = try authenticator.confirmation()
        pairingAuthenticator = authenticator

        try await sendAuthMessage(.authConfirm, PairingMessage(protocolVersion: PairingMessage.currentProtocolVersion, confirmation: confirmation))
    }

    /// Server: the client's confirmation MAC. Verifying it is what actually checks the client
    /// entered the right passcode. Replies with `authResult` either way so the client learns
    /// whether the server accepted, then marks the handshake complete on success.
    private func handleAuthConfirm(_ message: PairingMessage) async throws {
        guard isIncomingConnection, let authenticator = pairingAuthenticator,
              let clientConfirmation = message.confirmation else {
            throw PairingAuthenticator.PairingError.protocolViolation
        }
        do {
            try authenticator.verify(peerConfirmation: clientConfirmation)
        } catch {
            logger.log("networkConnection.handleAuthConfirm: client confirmation mismatch (likely wrong passcode), rejecting", type: .default)
            try await sendAuthMessage(.authResult, PairingMessage(protocolVersion: PairingMessage.currentProtocolVersion, accepted: false))
            throw error
        }
        try await sendAuthMessage(.authResult, PairingMessage(protocolVersion: PairingMessage.currentProtocolVersion, accepted: true))
        onAuthenticationSucceeded()
    }

    /// Client: the server's final accept/reject of the client's confirmation MAC.
    private func handleAuthResult(_ message: PairingMessage) throws {
        guard !isIncomingConnection else {
            throw PairingAuthenticator.PairingError.protocolViolation
        }
        guard message.accepted == true else {
            throw PairingAuthenticator.PairingError.confirmationMismatch
        }
        onAuthenticationSucceeded()
    }

    /// Encodes and sends a pairing message. Uses `sendRaw` rather than `sendAsyncWrapper`, since
    /// that wrapper waits for `isAuthenticated` and the migration state machine — both
    /// preconditions that don't hold yet while the handshake is running.
    private func sendAuthMessage(_ type: MigratorMessageType, _ message: PairingMessage) async throws {
        guard var data = "auth".data(using: .utf8),
              let infoDataLength = try? data.include(object: message) else {
            throw MigratorError.fileError(type: .noData)
        }
        let framerMessage = NWProtocolFramer.Message(migratorMessageType: type, infoLenght: UInt32(infoDataLength))
        let context = NWConnection.ContentContext(identifier: "Auth", metadata: [framerMessage])
        try await sendRaw(content: data, contentContext: context)
    }

    /// Sends data directly via `connection.send`, bypassing `sendAsyncWrapper`'s
    /// `awaitConnectionReadiness()`/token gating and retry logic. Used for messages that must
    /// go out regardless of the migration state machine: the pairing handshake messages, and
    /// the handshake-completion metadata (hostname/free space/device info) sent right after it
    /// succeeds. Gating those on `awaitConnectionReadiness()` raced against UI code that resets
    /// `migrationState` to `.initial` as soon as the connection is established, permanently
    /// starving the send since nothing else would move `migrationState` again afterwards.
    private func sendRaw(content: Data, contentContext: NWConnection.ContentContext) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: content, contentContext: contentContext, isComplete: true, completion: .contentProcessed({ error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }))
        }
    }

    /// Restores the connection by creating a new NWConnection with the same parameters
    /// This method should be called when the connection fails and needs to be re-established
    /// - Returns: True if restoration was initiated, false if this is an incoming connection or parameters are missing
    @discardableResult
    func restoreConnection() -> Bool {
        guard !isIncomingConnection, let endpoint = endpoint, passcode != nil else {
            logger.log("networkConnection.restoreConnection: cannot restore - incoming connection or missing parameters", type: .error)
            return false
        }
        
        logger.log("networkConnection.restoreConnection: cancelling old connection and creating new one", type: .default)

        // Cancel the old connection
        connection.forceCancel()

        // Re-run the pairing handshake on the new connection.
        isAuthenticated = false
        pairingAuthenticator = nil
        channelBinding = nil
        handshakeTimeoutWorkItem?.cancel()
        handshakeTimeoutWorkItem = nil
        pendingRequestTimeoutWorkItem?.cancel()
        pendingRequestTimeoutWorkItem = nil
        pendingRequestHostname = nil

        // Create a new connection with the same parameters
        let parameters = NWParameters(tlsIdentity: nil)
        connection = NWConnection(to: endpoint, using: parameters)

        // Re-setup all handlers
        setupConnectionHandlers()
        
        // Start the new connection
        connection.start(queue: .main)
        
        logger.log("networkConnection.restoreConnection: new connection started", type: .default)
        return true
    }
    
    // MARK: - Public Methods
    
    /// Asynchronously sends a file to the connected device.
    /// - Parameter file: The file to send.
    func sendFile(_ file: MigratorFile) async throws {
        if file.type == .app {
            try await self.sendFile(file.url.fullURL())
            MigrationReportController.shared.addMigratedApp(file.name)
        } else {
            try await _sendFile(file)
            try await sendSymlinks()
        }
    }
    
    /// Asynchronously sends a file to the connected device.
    /// - Parameter fileURL: The URL of the file to send.
    private func sendFile(_ fileURL: URL) async throws {
        try await _sendFile(at: fileURL)
        try await sendSymlinks()
    }
    
    /// Sends the hostname of the current device to the connected device. Sent right after the
    /// pairing handshake succeeds, so it uses `sendRaw` rather than `sendAsyncWrapper` - see
    /// `sendRaw`'s doc comment for why.
    func sendHostName() async throws {
        if let data = (Host.current().localizedName ?? "Connected Device").data(using: .utf8) {
            let message = NWProtocolFramer.Message(migratorMessageType: .hostname, infoLenght: 0)
            let context = NWConnection.ContentContext(identifier: "Hostname",
                                                      metadata: [message])
            try await sendRaw(content: data, contentContext: context)
        }
    }

    /// Sends the available free space of the current device to the connected device. Sent
    /// right after the pairing handshake succeeds, so it uses `sendRaw` rather than
    /// `sendAsyncWrapper` - see `sendRaw`'s doc comment for why.
    func sendAvailableFreeSpace() async throws {
        if let data = Utils.Common.freeSpaceOnDevice.description.data(using: .utf8) {
            let message = NWProtocolFramer.Message(migratorMessageType: .availableSpace, infoLenght: 0)
            let context = NWConnection.ContentContext(identifier: "FreeSpace",
                                                      metadata: [message])
            try await sendRaw(content: data, contentContext: context)
        }
    }
    
    func sendMigrationSize(_ size: Int) async throws {
        if let data = size.description.data(using: .utf8) {
            let message = NWProtocolFramer.Message(migratorMessageType: .metadata, infoLenght: 0)
            let context = NWConnection.ContentContext(identifier: "MigrationSize",
                                                      metadata: [message])
            try await sendAsyncWrapper(content: data, contentContext: context)
            onReadyToReceive.send(true)
        }
    }
    
    /// Tells the destination the migration was paused. Uses `sendRaw` because
    /// `sendAsyncWrapper` blocks while the migration state is `.paused`.
    func sendMigrationPaused() async throws {
        if let data = "Paused".data(using: .utf8) {
            let message = NWProtocolFramer.Message(migratorMessageType: .migrationPaused, infoLenght: 0)
            let context = NWConnection.ContentContext(identifier: "MigrationPaused",
                                                      metadata: [message])
            try await sendRaw(content: data, contentContext: context)
        }
    }
    
    /// Gracefully closes the connection for a user-initiated pause. `cancel()` (unlike
    /// `forceCancel()`) lets already-queued data drain first.
    func closeForPause() {
        logger.log("networkConnection.closeForPause: closing connection for pause", type: .default)
        connection.cancel()
    }
    
    func sendMigrationCompleted() async throws {
        if let data = "Completion".data(using: .utf8) {
            let message = NWProtocolFramer.Message(migratorMessageType: .result, infoLenght: 0)
            let context = NWConnection.ContentContext(identifier: "MigrationCompleted",
                                                      metadata: [message])
            try await sendAsyncWrapper(content: data, contentContext: context)
            isMigrationCompleted = true
        }
    }
    
    // MARK: - Private Methods
    
    /// A wrapper method to send data asynchronously over the network connection with retry capability.
    /// - Parameters:
    ///   - content: The data to be sent.
    ///   - contentContext: The context for the data being sent, including any associated metadata.
    ///   - maxRetries: Maximum number of retry attempts (default: 3)
    ///   - retryDelay: Delay in seconds between retries (default: 2)
    private func sendAsyncWrapper(content: Data,
                                  contentContext: NWConnection.ContentContext = .defaultMessage,
                                  maxRetries: Int = 5,
                                  retryDelay: TimeInterval = 2) async throws {
        logger.log("networkConnection.sendAsync: sending message \"\(contentContext.identifier)\"")
        
        var currentRetry = 0
        var lastError: Error?
        while currentRetry <= maxRetries {
            var tokenAcquired = false
            do {
                await MigrationController.shared.awaitConnectionReadiness()
                guard connection.state == .ready, isAuthenticated else {
                    logger.log("networkConnection.sendAsync: connection not ready (state: \(connection.state), authenticated: \(isAuthenticated)), throwing error to retry", type: .fault)
                    throw NSError(domain: "NetworkConnection", code: 1002,
                                 userInfo: [NSLocalizedDescriptionKey: "Connection not ready"])
                }
                
                await MigrationController.shared.acquireConnectionOperationToken()
                tokenAcquired = true
                
                defer {
                    if tokenAcquired {
                        Task {
                            await MigrationController.shared.releaseConnectionOperationToken()
                        }
                    }
                }
                
                return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    let state = ContinuationState()
                    
                    connection.send(content: content, contentContext: contentContext, isComplete: true, completion: .contentProcessed({ error in
                        Task {
                            if await state.tryResume() {
                                if let error = error {
                                    MLogger.main.log("networkConnection.sendAsync: error sending message \"\(contentContext.identifier)\" -> \"\(error.localizedDescription)\"", type: .error, category: .network)
                                    continuation.resume(throwing: error)
                                } else {
                                    MLogger.main.log("networkConnection.sendAsync: done sending message \"\(contentContext.identifier)\"", category: .network)
                                    continuation.resume()
                                }
                            }
                        }
                    }))
                }
            } catch {
                lastError = error
                currentRetry += 1
                if currentRetry <= maxRetries {
                    let backoffDelay = retryDelay * pow(2.0, Double(currentRetry - 1))
                    MLogger.main.log("networkConnection.sendAsync: retry \(currentRetry)/\(maxRetries) for message \"\(contentContext.identifier)\" -> \"\(error.localizedDescription)\" — waiting \(backoffDelay)s before retry", type: .fault, category: .network)
                    try await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
                } else {
                    MLogger.main.log("networkConnection.sendAsync: exhausted all \(maxRetries) retries for message \"\(contentContext.identifier)\" -> \"\(error.localizedDescription)\"", type: .error, category: .network)
                    MigrationReportController.shared.addError("Failed to send message \"\(contentContext.identifier)\" after \(maxRetries) retries: \(error.localizedDescription)")
                    MigrationController.shared.attemptConnectionRepair(reason: "send exhausted \(maxRetries) retries for \"\(contentContext.identifier)\"")
                }
            }
        }
        if let lastError = lastError {
            throw lastError
        } else {
            throw NSError(domain: "NetworkConnection", code: 1000,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to send after \(maxRetries) retries"])
        }
    }
    
    /// Logs a symlink whose target genuinely doesn't exist. A relative target is resolved against the
    /// link's own directory (not the process's working directory), and a dangling link is normal
    /// (build artifacts, Carthage checkouts), so this is informational, not a fault.
    private func logDanglingSymlinkIfNeeded(at linkURL: URL, destination: String) {
        let resolved = destination.hasPrefix("/")
            ? destination
            : linkURL.deletingLastPathComponent().appendingPathComponent(destination).path
        if !FileManager.default.fileExists(atPath: resolved) {
            logger.log("networkConnection.sendFile: symbolic link \"\(linkURL.path)\" points to non-existent path \"\(destination)\"", type: .default)
        }
    }

    private func closeFile(_ fileHandle: FileHandle) throws {
        do {
            try fileHandle.close()
        } catch let error {
            throw MigratorError.fileError(type: .failedDuringFileHandling(error: error))
        }
    }
    
    /// Handles the sending of a file, breaking it into chunks if necessary, and collecting symbolic links as needed.
    /// - Parameter file: The file to send.
    private func _sendFile(_ file: MigratorFile) async throws {
        logger.log("networkConnection.sendFile: preparing file \"\(file.url.fullURL().relativePath)\"")
        let chunkSize: UInt64 = 30_000_000
        
        // Opening a named pipe for reading blocks until something writes to it, and this runs on the
        // main actor: reading one freezes the app. Dataless placeholders would be downloaded.
        if Utils.FileManagerHelpers.shouldSkipForTransfer(file.url.fullURL()) {
            logger.log("networkConnection.sendFile: skipping special, dataless or regenerable item \"\(file.url.fullURL().relativePath)\"", type: .default)
            return
        }
        
        if file.type == .symlink {
            do {
                let destinationPath = try FileManager.default.destinationOfSymbolicLink(atPath: file.url.fullURL().relativePath)
                
                if destinationPath == file.url.fullURL().relativePath {
                    logger.log("networkConnection.sendFile: detected circular symlink at \"\(file.url.fullURL().relativePath)\"", type: .error)
                    MigrationReportController.shared.addError("Skipped circular symbolic link: \(file.url.fullURL().relativePath)")
                    return
                }
                
                guard let destinationURL = URL(string: destinationPath) else {
                    logger.log("networkConnection.sendFile: impossible to create URL from \"\(destinationPath)\"", type: .error)
                    MigrationReportController.shared.addError("Skipped invalid symbolic link: \(file.url.fullURL().relativePath) -> \(destinationPath)")
                    return
                }
                
                logDanglingSymlinkIfNeeded(at: file.url.fullURL(), destination: destinationPath)
                
                logger.log("networkConnection.sendFile: file \"\(file.url.fullURL().relativePath)\" is alias of \"\(destinationPath)\"")
                let destinationTrackedURL = MigratorFileURL(with: destinationURL)
                let sourceTrackedURL = MigratorFileURL(with: file.url.fullURL())
                
                if destinationTrackedURL.source == .unknown {
                    let infoData = SymbolicLinkMessage(source: sourceTrackedURL, absoluteDestination: MigratorFileURL(with: file.url.fullURL().deletingLastPathComponent()), relativeDestination: destinationPath)
                    symlinks.append(infoData)
                } else {
                    let infoData = SymbolicLinkMessage(source: sourceTrackedURL, absoluteDestination: MigratorFileURL(with: URL(string: destinationPath)!))
                    symlinks.append(infoData)
                }
                return
            } catch {
                logger.log("networkConnection.sendFile: impossible to create symlink -> \"\(error.localizedDescription)\"", type: .error)
                MigrationReportController.shared.addError("Failed to process symbolic link: \(file.url.fullURL().relativePath) - \(error.localizedDescription)")
            }
        }
        
        guard FileManager.default.fileExists(atPath: file.url.fullURL().relativePath) else {
            logger.log("networkConnection.sendFile: file \"\(file.url.fullURL().relativePath)\" doesn't exist", type: .error)
            throw MigratorError.fileError(type: .noData)
        }
            
        var attributes: [FileAttributeKey: Any] = [:]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: file.url.fullURL().relativePath) as [FileAttributeKey: Any]
        } catch {
            logger.log("networkConnection.sendFile: failed to get attributes of file \"\(file.url.fullURL().relativePath)\" -> \"\(error.localizedDescription)\"", type: .error)
            MigrationReportController.shared.addError("Failed to get attributes for file: \(file.url.fullURL().relativePath)")
        }
        
        if file.type == .directory || file.type == .app {
            let infoData = FileMessage(with: file.url.fullURL(), part: 0, attributes: attributes)
            guard var data = "directory".data(using: .utf8),
                  let infoDataLenght = try? data.include(object: infoData) else {
                throw MigratorError.internalError(type: .data)
            }
            let message = NWProtocolFramer.Message(migratorMessageType: .directory, infoLenght: UInt32(infoDataLenght))
            let context = NWConnection.ContentContext(identifier: "Directory",
                                                      metadata: [message])
            logger.log("networkConnection.sendFile: sending data of directory at \"\(file.url.fullURL().relativePath)\"")
            try await sendAsyncWrapper(content: data, contentContext: context)
            self.onFileSent.send(1)
            self.onBytesSent.send(FileScanner.allocatedSize(of: file.url.fullURL()))
            
            logger.log("networkConnection.sendFile: start sending content of directory \"\(file.url.fullURL().relativePath)\"")
            let childs = file.childFiles.isEmpty ? await file.fetchUnretainedChilds() : file.childFiles
            for child in childs {
                do {
                    try await sendFile(child)
                } catch {
                    MigrationReportController.shared.addError("Failed to send file: \(child.url.fullURL().relativePath) - with error: \"\(error.localizedDescription)\"")
                    logger.log("networkConnection.sendFile: failed to send file \"\(child.url.fullURL().relativePath)\" -> \"\(error.localizedDescription)\"", type: .error)
                }
            }
            logger.log("networkConnection.sendFile: sending properties of directory at \"\(file.url.fullURL().relativePath)\"")
            try await sendAsyncWrapper(content: data, contentContext: context)
            return
        }
        
        guard let fileHandle = FileHandle(forReadingAtPath: file.url.fullURL().relativePath) else {
            logger.log("networkConnection.sendFile: failed to handle file \"\(file.url.fullURL().relativePath)\", impossible to read", type: .error)
            throw MigratorError.fileError(type: .failedDuringFileHandling())
        }
        
        defer {
            try? fileHandle.close()
        }

        var availableBytes = (attributes as NSDictionary).fileSize()
        var parsedBytes: UInt64 = 0
        
        // Progress is reported in allocated-size terms: the unit the migration size was computed in.
        let totalBytes = availableBytes
        let allocatedBytes = FileScanner.allocatedSize(of: file.url.fullURL())
        var reportedBytes = 0
        
        logger.log("networkConnection.sendFile: start sending data of file \"\(file.url.fullURL().relativePath)\"")
        if availableBytes > chunkSize {
            var partNumber: UInt32 = 0
            do {
                try fileHandle.seek(toOffset: parsedBytes)
            } catch let error {
                logger.log("networkConnection.sendFile: failed to handle file \"\(file.url.fullURL().relativePath)\", impossible to read", type: .error)
                throw MigratorError.fileError(type: .failedDuringFileHandling(error: error))
            }
            while availableBytes > 0 {
                let infoData = FileMessage(with: file.url.fullURL(), part: Int(partNumber), byteOffset: parsedBytes, attributes: attributes)
                guard var chunk = try? fileHandle.read(upToCount: Int(min(chunkSize, availableBytes))),
                      let infoDataLenght = try? chunk.include(object: infoData) else {
                    logger.log("networkConnection.sendFile: failed to handle file \"\(file.url.fullURL().relativePath)\", impossible to read", type: .error)
                    throw MigratorError.fileError(type: .noData)
                }
                let message = NWProtocolFramer.Message(migratorMessageType: .multipartFile, infoLenght: UInt32(infoDataLenght))
                let context = NWConnection.ContentContext(identifier: "Chunk",
                                                          metadata: [message])
                
                try await sendAsyncWrapper(content: chunk, contentContext: context)
                // A chunk accounts for its share of the file's allocated size (this also keeps sparse
                // or compressed files, whose allocated size is far from their length, from overshooting).
                let chunkProgress = totalBytes > 0
                    ? Int(Double(allocatedBytes) * Double(min(chunkSize, availableBytes)) / Double(totalBytes))
                    : 0
                reportedBytes += chunkProgress
                self.onBytesSent.send(chunkProgress)
                            
                parsedBytes += min(chunkSize, availableBytes)
                if availableBytes > chunkSize {
                    availableBytes -= chunkSize
                } else {
                    availableBytes = 0
                }
                partNumber += 1
                
                do {
                    try fileHandle.seek(toOffset: parsedBytes)
                } catch let error {
                    logger.log("networkConnection.sendFile: failed to handle file \"\(file.url.fullURL().relativePath)\", impossible to read", type: .error)
                    throw MigratorError.fileError(type: .failedDuringFileHandling(error: error))
                }
            }
            // Settle the rounding so the file accounts for exactly its allocated size.
            if allocatedBytes != reportedBytes {
                self.onBytesSent.send(allocatedBytes - reportedBytes)
            }
            self.onFileSent.send(1)
        } else if availableBytes == 0 {
            let infoObject = FileMessage(with: file.url.fullURL(), part: 0, attributes: attributes)
            let infoData = try JSONEncoder().encode(infoObject)
            let message = NWProtocolFramer.Message(migratorMessageType: .file, infoLenght: UInt32(infoData.count))
            let context = NWConnection.ContentContext(identifier: "EmptyFile",
                                                      metadata: [message])
            try await sendAsyncWrapper(content: infoData, contentContext: context)
            self.onBytesSent.send(allocatedBytes)
            self.onFileSent.send(1)
        } else {
            let infoData = FileMessage(with: file.url.fullURL(), part: 0, attributes: attributes)
            guard var data = try? fileHandle.readToEnd(),
                  let infoDataLenght = try? data.include(object: infoData) else {
                throw MigratorError.fileError(type: .noData)
            }
            let message = NWProtocolFramer.Message(migratorMessageType: .file, infoLenght: UInt32(infoDataLenght))
            let context = NWConnection.ContentContext(identifier: "File",
                                                      metadata: [message])
            
            try await sendAsyncWrapper(content: data, contentContext: context)
            self.onBytesSent.send(allocatedBytes)
            self.onFileSent.send(1)
        }
        logger.log("networkConnection.sendFile: done sending file \"\(file.url.fullURL().relativePath)\"")
    }
    
    /// Handles the sending of a file, breaking it into chunks if necessary, and collecting symbolic links as needed.
    /// - Parameter fileURL: The URL of the file to send.
    private func _sendFile(at fileURL: URL) async throws {
        logger.log("networkConnection.sendFile: preparing file \"\(fileURL.relativePath)\"")
        
        let chunkSize: UInt64 = 33_554_432
        var isDirectory: ObjCBool = false
        
        // Never read dataless iCloud/File Provider placeholders (it would force a download) and don't
        // send cache folders the destination regenerates. Directory children reach this method too.
        if Utils.FileManagerHelpers.shouldSkipForTransfer(fileURL) {
            logger.log("networkConnection.sendFile: skipping dataless or regenerable item \"\(fileURL.relativePath)\"", type: .default)
            return
        }
        
        if let destinationPath = try? FileManager.default.destinationOfSymbolicLink(atPath: fileURL.relativePath) {
            // Check for circular references
            if destinationPath == fileURL.relativePath {
                logger.log("networkConnection.sendFile: detected circular symlink at \"\(fileURL.relativePath)\"", type: .error)
                MigrationReportController.shared.addError("Skipped circular symbolic link: \(fileURL.relativePath)")
                return
            }
            
            logger.log("networkConnection.sendFile: file \"\(fileURL.relativePath)\" is alias of \"\(destinationPath)\"")
            guard let destinationURL = URL(string: destinationPath) else {
                logger.log("networkConnection.sendFile: impossible to create URL from \"\(destinationPath)\"", type: .error)
                MigrationReportController.shared.addError("Skipped invalid symbolic link: \(fileURL.relativePath) -> \(destinationPath)")
                return
            }
            
            // Check if destination path exists (non-critical, just log it)
            logDanglingSymlinkIfNeeded(at: fileURL, destination: destinationPath)
            
            let destinationTrackedURL = MigratorFileURL(with: destinationURL)
            let sourceTrackedURL = MigratorFileURL(with: fileURL)
            if destinationTrackedURL.source == .unknown {
                let infoData = SymbolicLinkMessage(source: sourceTrackedURL, absoluteDestination: MigratorFileURL(with: fileURL.deletingLastPathComponent()), relativeDestination: destinationPath)
                symlinks.append(infoData)
            } else {
                let infoData = SymbolicLinkMessage(source: sourceTrackedURL, absoluteDestination: MigratorFileURL(with: URL(string: destinationPath)!))
                symlinks.append(infoData)
            }
            return
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.relativePath, isDirectory: &isDirectory) else {
            logger.log("networkConnection.sendFile: file \"\(fileURL.relativePath)\" doesn't exist", type: .error)
            throw MigratorError.fileError(type: .noData)
        }
        
        logger.log("networkConnection.sendFile: file \"\(fileURL.relativePath)\" is directory -> \"\(isDirectory.description)\"")
        
        var attributes: [FileAttributeKey: Any] = [:]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: fileURL.relativePath) as [FileAttributeKey: Any]
        } catch {
            logger.log("networkConnection.sendFile: failed to get attributes of file \"\(fileURL.relativePath)\" -> \"\(error.localizedDescription)\"", type: .error)
            MigrationReportController.shared.addError("Failed to get attributes for file: \(fileURL.relativePath)")
        }
        
        guard !isDirectory.boolValue else {
            let infoData = FileMessage(with: fileURL, part: 0, attributes: attributes)
            guard var data = "directory".data(using: .utf8),
                  let infoDataLenght = try? data.include(object: infoData) else {
                throw MigratorError.internalError(type: .data)
            }
            let message = NWProtocolFramer.Message(migratorMessageType: .directory, infoLenght: UInt32(infoDataLenght))
            let context = NWConnection.ContentContext(identifier: "Directory",
                                                      metadata: [message])
            logger.log("networkConnection.sendFile: sending data of directory at \"\(fileURL.relativePath)\"")
            try await sendAsyncWrapper(content: data, contentContext: context)
            self.onFileSent.send(1)
            self.onBytesSent.send(FileScanner.allocatedSize(of: fileURL))
            
            let childFilePaths = try FileManager.default.contentsOfDirectory(atPath: fileURL.relativePath)
            logger.log("networkConnection.sendFile: start sending content of directory \"\(fileURL.relativePath)\"")
            for childFilePath in childFilePaths {
                guard !childFilePath.isEmpty else { return }
                let childURL = fileURL.appendingPathComponent(childFilePath, isDirectory: isDirectory.boolValue)
                // The scanner only filtered the first levels of the selection: apply the exclusion
                // rules (extensions, prefixes, dataless, caches...) to everything below it too.
                if Utils.FileManagerHelpers.shouldSkipDescendantForTransfer(childURL) {
                    logger.log("networkConnection.sendFile: skipping excluded item \"\(childURL.relativePath)\"", type: .default)
                    continue
                }
                do {
                    try await sendFile(childURL)
                } catch {
                    MigrationReportController.shared.addError("Failed to send file: \(childFilePath) - with error: \"\(error.localizedDescription)\"")
                }
            }
            logger.log("networkConnection.sendFile: sending properties of directory at \"\(fileURL.relativePath)\"")
            try await sendAsyncWrapper(content: data, contentContext: context)
            return
        }
        guard let fileHandle = FileHandle(forReadingAtPath: fileURL.relativePath) else {
            logger.log("networkConnection.sendFile: failed to handle file \"\(fileURL.relativePath)\", impossible to read", type: .error)
            throw MigratorError.fileError(type: .failedDuringFileHandling())
        }
        
        defer {
            try? fileHandle.close()
        }

        var availableBytes = (attributes as NSDictionary).fileSize()
        var parsedBytes: UInt64 = 0
    
        // Progress is reported in allocated-size terms: the unit the migration size was computed in.
        let totalBytes = availableBytes
        let allocatedBytes = FileScanner.allocatedSize(of: fileURL)
        var reportedBytes = 0
        
        logger.log("networkConnection.sendFile: start sending data of file \"\(fileURL.relativePath)\"")
        if availableBytes > chunkSize {
            var partNumber: UInt32 = 0
            do {
                try fileHandle.seek(toOffset: parsedBytes)
            } catch let error {
                logger.log("networkConnection.sendFile: failed to handle file \"\(fileURL.relativePath)\", impossible to read", type: .error)
                throw MigratorError.fileError(type: .failedDuringFileHandling(error: error))
            }
            while availableBytes > 0 {
                let infoData = FileMessage(with: fileURL, part: Int(partNumber), attributes: attributes)
                guard var chunk = try? fileHandle.read(upToCount: Int(min(chunkSize, availableBytes))),
                      let infoDataLenght = try? chunk.include(object: infoData)else {
                    logger.log("networkConnection.sendFile: failed to handle file \"\(fileURL.relativePath)\", impossible to read", type: .error)
                    throw MigratorError.fileError(type: .noData)
                }
                let message = NWProtocolFramer.Message(migratorMessageType: .multipartFile, infoLenght: UInt32(infoDataLenght))
                let context = NWConnection.ContentContext(identifier: "Chunk",
                                                          metadata: [message])
                
                try await sendAsyncWrapper(content: chunk, contentContext: context)
                // A chunk accounts for its share of the file's allocated size (this also keeps sparse
                // or compressed files, whose allocated size is far from their length, from overshooting).
                let chunkProgress = totalBytes > 0
                    ? Int(Double(allocatedBytes) * Double(min(chunkSize, availableBytes)) / Double(totalBytes))
                    : 0
                reportedBytes += chunkProgress
                self.onBytesSent.send(chunkProgress)
                            
                parsedBytes += min(chunkSize, availableBytes)
                if availableBytes > chunkSize {
                    availableBytes -= chunkSize
                } else {
                    availableBytes = 0
                }
                partNumber += 1
                
                do {
                    try fileHandle.seek(toOffset: parsedBytes)
                } catch let error {
                    logger.log("networkConnection.sendFile: failed to handle file \"\(fileURL.relativePath)\", impossible to read", type: .error)
                    throw MigratorError.fileError(type: .failedDuringFileHandling(error: error))
                }
            }
            // Settle the rounding so the file accounts for exactly its allocated size.
            if allocatedBytes != reportedBytes {
                self.onBytesSent.send(allocatedBytes - reportedBytes)
            }
            self.onFileSent.send(1)
        } else if availableBytes == 0 {
            let infoObject = FileMessage(with: fileURL, part: 0, attributes: attributes)
            let infoData = try JSONEncoder().encode(infoObject)
            let message = NWProtocolFramer.Message(migratorMessageType: .file, infoLenght: UInt32(infoData.count))
            let context = NWConnection.ContentContext(identifier: "EmptyFile",
                                                      metadata: [message])
            try await sendAsyncWrapper(content: infoData, contentContext: context)
            self.onBytesSent.send(allocatedBytes)
            self.onFileSent.send(1)
        } else {
            let infoData = FileMessage(with: fileURL, part: 0, attributes: attributes)
            guard var data = try? fileHandle.readToEnd(),
                  let infoDataLenght = try? data.include(object: infoData) else {
                throw MigratorError.fileError(type: .noData)
            }
            let message = NWProtocolFramer.Message(migratorMessageType: .file, infoLenght: UInt32(infoDataLenght))
            let context = NWConnection.ContentContext(identifier: "File",
                                                      metadata: [message])
            
            try await sendAsyncWrapper(content: data, contentContext: context)
            self.onBytesSent.send(allocatedBytes)
            self.onFileSent.send(1)
        }
        logger.log("networkConnection.sendFile: done sending file \"\(fileURL.relativePath)\"")
    }
    
    /// Sends collected symbolic links to the connected device.
    private func sendSymlinks() async throws {
        logger.log("networkConnection.sendSymlinks: start sending collected symlinks")
        for message in symlinks {
            guard var data = "link".data(using: .utf8),
                  let infoDataLenght = try? data.include(object: message) else {
                throw MigratorError.fileError(type: .noData)
            }
            let message = NWProtocolFramer.Message(migratorMessageType: .symlink, infoLenght: UInt32(infoDataLenght))
            let context = NWConnection.ContentContext(identifier: "SymbolicLink",
                                                      metadata: [message])
            try await sendAsyncWrapper(content: data, contentContext: context)
            // The size scan counted every symbolic link as an item, so progress has to as well.
            self.onFileSent.send(1)
        }
        symlinks = []
        logger.log("networkConnection.sendSymlinks: done sending collected symlinks")
    }
    
    /// Sends collected symbolic links to the connected device.
    func sendDefaults(_ object: DefaultsMessage) async throws {
        logger.log("networkConnection.sendDefaults: start sending \(object.key) UserDefaults")
        guard var data = "defaults".data(using: .utf8),
              let infoDataLenght = try? data.include(object: object) else {
            throw MigratorError.fileError(type: .noData)
        }
        let message = NWProtocolFramer.Message(migratorMessageType: .defaults, infoLenght: UInt32(infoDataLenght))
        let context = NWConnection.ContentContext(identifier: "UserDefaults",
                                                  metadata: [message])
        try await sendAsyncWrapper(content: data, contentContext: context)
        logger.log("networkConnection.sendDefaults: done sending \(object.key) UserDefaults")
    }

    /// Sends one macOS preferences domain's values to the connected device.
    /// - Parameters:
    ///   - object: Identifies the domain and the `PreferenceGroup` it belongs to.
    ///   - payload: The binary property list of the domain's values.
    func sendPreferences(_ object: PreferencesMessage, payload: Data) async throws {
        logger.log("networkConnection.sendPreferences: start sending domain \"\(object.applicationID ?? "global")\" for group \"\(object.groupID)\"")
        var data = payload
        guard let infoDataLenght = try? data.include(object: object) else {
            throw MigratorError.fileError(type: .noData)
        }
        let message = NWProtocolFramer.Message(migratorMessageType: .preferences, infoLenght: UInt32(infoDataLenght))
        let context = NWConnection.ContentContext(identifier: "Preferences",
                                                  metadata: [message])
        try await sendAsyncWrapper(content: data, contentContext: context)
        self.onBytesSent.send(data.count)
        logger.log("networkConnection.sendPreferences: done sending domain \"\(object.applicationID ?? "global")\" for group \"\(object.groupID)\"")
    }

    /// Sends device information including architecture to the connected device. Sent right
    /// after the pairing handshake succeeds, so it uses `sendRaw` rather than `sendAsyncWrapper`
    /// - see `sendRaw`'s doc comment for why.
    func sendDeviceInfo() async throws {
        let deviceInfo = DeviceInfoMessage()
        logger.log("networkConnection.sendDeviceInfo: sending device info - architecture: \(deviceInfo.architecture), OS: \(deviceInfo.osVersion)")

        guard var data = "deviceInfo".data(using: .utf8),
              let infoDataLength = try? data.include(object: deviceInfo) else {
            throw MigratorError.fileError(type: .noData)
        }

        let message = NWProtocolFramer.Message(migratorMessageType: .deviceInfo, infoLenght: UInt32(infoDataLength))
        let context = NWConnection.ContentContext(identifier: "DeviceInfo",
                                                  metadata: [message])
        try await sendRaw(content: data, contentContext: context)
        logger.log("networkConnection.sendDeviceInfo: device info sent successfully")
    }
    
    /// Receives and processes the next incoming message from the connected device.
    private func receiveNextMessage() {
        switch connection.state {
        case .ready:
            logger.log("networkConnection.receiveNextMessage: waiting for new messages")
        case .cancelled:
            logger.log("networkConnection.receiveNextMessage: connection cancelled, stopping message reception", type: .default)
            return
        case .failed:
            logger.log("networkConnection.receiveNextMessage: connection failed, stopping message reception", type: .error)
            return
        default:
            logger.log("networkConnection.receiveNextMessage: connection not ready, state: \(connection.state), scheduling retry in 10 seconds.", type: .error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                self?.receiveNextMessage()
            }
            return
        }
        
        connection.receiveMessage { [weak self] (content, context, _, error) in
            guard let self = self else { return }
            // `receiveMessage`'s completion isn't `@MainActor`-annotated, but `connection` was
            // started on the `.main` queue, so this always fires there.
            MainActor.assumeIsolated {
            var shouldAutoReceiveNext = true
            defer {
                if shouldAutoReceiveNext {
                    if let error = error {
                        self.logger.log("networkConnection.receiveNextMessage: failed to receive message -> \"\(error.localizedDescription)\"", type: .error)
                        if self.connection.state == .ready {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                                self?.receiveNextMessage()
                            }
                        } else {
                            self.logger.log("networkConnection.receiveNextMessage: connection no longer ready after receive error, stopping message reception", type: .default)
                        }
                    } else {
                        self.receiveNextMessage()
                    }
                }
            }
            if let migratorMessage = context?.protocolMetadata(definition: MigratorNetworkProtocol.definition) as? NWProtocolFramer.Message {
                let messageType = migratorMessage.migratorMessageType
                let isPairingMessage: Bool = [.pairingRequest, .pairingDecision, .pairingCancelled, .authHello, .authResponse, .authConfirm, .authResult].contains(messageType)
                guard self.isAuthenticated || isPairingMessage else {
                    self.logger.log("networkConnection.receiveNextMessage: rejecting \"\(messageType)\" before the pairing handshake completed", type: .error)
                    self.failAuthentication()
                    return
                }
                switch messageType {
                case .pairingRequest:
                    self.logger.log("networkConnection.receiveNextMessage: pairingRequest message received", type: .default)
                    guard var data = content else { return }
                    do {
                        let message = try data.extractObject(from: 0..<Int(migratorMessage.migratorMessageInfoLenght), ofType: PairingMessage.self)
                        try self.handlePairingRequest(message)
                    } catch {
                        self.logger.log("networkConnection.receiveNextMessage: failed to handle pairingRequest -> \"\(error.localizedDescription)\"", type: .error)
                        self.failAuthentication()
                    }
                case .pairingDecision:
                    self.logger.log("networkConnection.receiveNextMessage: pairingDecision message received", type: .default)
                    guard var data = content else { return }
                    do {
                        let message = try data.extractObject(from: 0..<Int(migratorMessage.migratorMessageInfoLenght), ofType: PairingMessage.self)
                        try self.handlePairingDecision(message)
                    } catch {
                        self.logger.log("networkConnection.receiveNextMessage: failed to handle pairingDecision -> \"\(error.localizedDescription)\"", type: .error)
                        self.failAuthentication()
                    }
                case .pairingCancelled:
                    self.logger.log("networkConnection.receiveNextMessage: pairingCancelled message received", type: .default)
                    guard var data = content else { return }
                    do {
                        let message = try data.extractObject(from: 0..<Int(migratorMessage.migratorMessageInfoLenght), ofType: PairingMessage.self)
                        try self.handlePairingCancelled(message)
                    } catch {
                        self.logger.log("networkConnection.receiveNextMessage: failed to handle pairingCancelled -> \"\(error.localizedDescription)\"", type: .error)
                        self.failAuthentication()
                    }
                case .authHello:
                    self.logger.log("networkConnection.receiveNextMessage: authHello message received", type: .default)
                    guard var data = content else { return }
                    Task {
                        do {
                            let message = try data.extractObject(from: 0..<Int(migratorMessage.migratorMessageInfoLenght), ofType: PairingMessage.self)
                            try await self.handleAuthHello(message)
                        } catch {
                            self.logger.log("networkConnection.receiveNextMessage: failed to handle authHello -> \"\(error.localizedDescription)\"", type: .error)
                            self.failAuthentication()
                        }
                    }
                case .authResponse:
                    self.logger.log("networkConnection.receiveNextMessage: authResponse message received", type: .default)
                    guard var data = content else { return }
                    Task {
                        do {
                            let message = try data.extractObject(from: 0..<Int(migratorMessage.migratorMessageInfoLenght), ofType: PairingMessage.self)
                            try await self.handleAuthResponse(message)
                        } catch {
                            self.logger.log("networkConnection.receiveNextMessage: failed to handle authResponse -> \"\(error.localizedDescription)\"", type: .error)
                            self.failAuthentication()
                        }
                    }
                case .authConfirm:
                    self.logger.log("networkConnection.receiveNextMessage: authConfirm message received", type: .default)
                    guard var data = content else { return }
                    Task {
                        do {
                            let message = try data.extractObject(from: 0..<Int(migratorMessage.migratorMessageInfoLenght), ofType: PairingMessage.self)
                            try await self.handleAuthConfirm(message)
                        } catch {
                            self.logger.log("networkConnection.receiveNextMessage: failed to handle authConfirm -> \"\(error.localizedDescription)\"", type: .error)
                            let reason: PairingFailureReason = (error as? PairingAuthenticator.PairingError) == .confirmationMismatch ? .wrongCode : .other
                            self.failAuthentication(reason: reason)
                        }
                    }
                case .authResult:
                    self.logger.log("networkConnection.receiveNextMessage: authResult message received", type: .default)
                    guard var data = content else { return }
                    do {
                        let message = try data.extractObject(from: 0..<Int(migratorMessage.migratorMessageInfoLenght), ofType: PairingMessage.self)
                        try self.handleAuthResult(message)
                    } catch {
                        self.logger.log("networkConnection.receiveNextMessage: failed to handle authResult -> \"\(error.localizedDescription)\"", type: .error)
                        self.failAuthentication()
                    }
                case .hostname:
                    self.logger.log("networkConnection.receiveNextMessage: hostname message received", type: .default)
                    if let data = content,
                        let hostname = String(data: data, encoding: .utf8) {
                        self.connectedDeviceHostName = hostname
                    } else {
                        self.logger.log("networkConnection.receiveNextMessage: impossible to decode hostname", type: .error)
                    }
                case .symlink:
                    self.logger.log("networkConnection.receiveNextMessage: symlink message received")
                    do {
                        if var data = content {
                            let messageInfo = try data.extractObject(from: 0..<Int(migratorMessage.migratorMessageInfoLenght), ofType: SymbolicLinkMessage.self)
                            self.logger.log("networkConnection.receiveNextMessage: symlink source \"\(messageInfo.source.relativePath)\"")
                            self.logger.log("networkConnection.receiveNextMessage: symlink relative destination \"\(messageInfo.relativeDestination ?? "nil")\"")
                            self.logger.log("networkConnection.receiveNextMessage: symlink absolute destination \"\(messageInfo.absoluteDestination.relativePath)\"")

                            var destinationPath = ""
                            if let relativeDestination = messageInfo.relativeDestination {
                                destinationPath = relativeDestination
                            } else {
                                destinationPath = messageInfo.absoluteDestination.fullURL().relativePath
                            }

                            // The link and its target both come from the peer: confine them to the
                            // directories a migration may write to before touching the disk.
                            let linkURL: URL
                            do {
                                linkURL = try messageInfo.source.validatedReceiveURL(resolvingFinalComponent: false)
                                try MigratorFileURL.validateSymlinkTarget(destinationPath, linkURL: linkURL)
                            } catch {
                                self.logger.log("networkConnection.receiveNextMessage: rejected symbolic link \"\(messageInfo.source.relativePath)\" -> \"\(destinationPath)\": \(error.localizedDescription)", type: .error)
                                MigrationReportController.shared.addError("Rejected unsafe symbolic link: \(messageInfo.source.relativePath) -> \(destinationPath)")
                                break
                            }

                            if linkURL.path == destinationPath {
                                self.logger.log("networkConnection.receiveNextMessage: detected circular symlink, skipping", type: .error)
                                MigrationReportController.shared.addError("Skipped circular symbolic link: \(linkURL.path)")
                                break
                            }
                            let parentDir = linkURL.deletingLastPathComponent()
#if !DEBUG
                            if !FileManager.default.fileExists(atPath: parentDir.path) {
                                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                            }
                            // `lstat` semantics: remove the link itself, never what it points to.
                            if (try? FileManager.default.attributesOfItem(atPath: linkURL.path)) != nil {
                                try FileManager.default.removeItem(atPath: linkURL.path)
                            }
                            try FileManager.default.createSymbolicLink(atPath: linkURL.path, withDestinationPath: destinationPath)
#endif
                        }
                    } catch let error {
                        self.logger.log("networkConnection.receiveNextMessage: failed to create symbolic link -> \"\(error.localizedDescription)\"", type: .error)
                    }
                case .file:
                    self.logger.log("networkConnection.receiveNextMessage: file message received")
                    if var data = content {
                        do {
                            let messageInfo = try data.extractObject(from: 0..<Int(migratorMessage.migratorMessageInfoLenght), ofType: FileMessage.self)
                            self.onBytesReceived.send(data.count)
                            self.logger.log("networkConnection.receiveNextMessage: file source \"\(messageInfo.source.relativePath)\"")
                            shouldAutoReceiveNext = false
                            let fileData = data
                            Task.detached(priority: .utility) { [weak self] in
                                guard let self else { return }
                                do {
                                    try self.writeReceivedFile(fileData, messageInfo: messageInfo)
                                } catch {
                                    self.logger.log("networkConnection.receiveNextMessage: failed to write file -> \"\(error.localizedDescription)\"", type: .error)
                                }
                                DispatchQueue.main.async {
                                    self.receiveNextMessage()
                                }
                            }
                        } catch let error {
                            self.logger.log("networkConnection.receiveNextMessage: failed to write file -> \"\(error.localizedDescription)\"", type: .error)
                        }
                    }
                case .directory:
                    self.logger.log("networkConnection.receiveNextMessage: directory message received")
                    do {
                        if var data = content {
                            let messageInfo = try data.extractObject(from: 0..<Int(migratorMessage.migratorMessageInfoLenght), ofType: FileMessage.self)
                            self.logger.log("networkConnection.receiveNextMessage: directory source \"\(messageInfo.source.relativePath)\"")
                            let directoryURL: URL
                            do {
                                directoryURL = try messageInfo.source.validatedReceiveURL()
                            } catch {
                                self.logger.log("networkConnection.receiveNextMessage: rejected directory \"\(messageInfo.source.relativePath)\": \(error.localizedDescription)", type: .error)
                                MigrationReportController.shared.addError("Rejected unsafe directory path: \(messageInfo.source.relativePath)")
                                break
                            }
#if !DEBUG
                            if FileManager.default.fileExists(atPath: directoryURL.path) {
                                try FileManager.default.setAttributes(messageInfo.sanitizedDirectoryAttributes, ofItemAtPath: directoryURL.path)
                            } else {
                                try FileManager.default.createDirectory(atPath: directoryURL.path, withIntermediateDirectories: true, attributes: messageInfo.sanitizedDirectoryAttributes)
                            }
#endif
                        }
                    } catch let error {
                        self.logger.log("networkConnection.receiveNextMessage: failed to create/update directory -> \"\(error.localizedDescription)\"", type: .error)
                    }
                case .migrationPaused:
                    self.logger.log("networkConnection.receiveNextMessage: migrationPaused message received", type: .default)
                    self.onMigrationPaused.send()
                case .result:
                    self.logger.log("networkConnection.receiveNextMessage: result message received", type: .default)
                    self.isMigrationCompleted = true
                    shouldAutoReceiveNext = false
                case .invalid:
                    self.logger.log("networkConnection.receiveNextMessage: invalid message received", type: .default)
                case .metadata:
                    self.logger.log("networkConnection.receiveNextMessage: metadata message received", type: .default)
                    if let data = content,
                        let migrationSize = String(data: data, encoding: .utf8) {
                        self.migrationSizeInBytes = Int(migrationSize) ?? 0
                    } else {
                        self.logger.log("networkConnection.receiveNextMessage: failed to decode metadata", type: .error)
                    }
                case .availableSpace:
                    self.logger.log("networkConnection.receiveNextMessage: availableSpace message received", type: .default)
                    if let data = content,
                        let freeSpace = String(data: data, encoding: .utf8) {
                        self.connectedDeviceAvailableSpace = Int(freeSpace) ?? 0
                    } else {
                        self.logger.log("networkConnection.receiveNextMessage: failed to decode availableSpace", type: .error)
                    }
                case .multipartFile:
                    self.logger.log("networkConnection.receiveNextMessage: multipart file message received")
                    guard var data = content else {
                        self.logger.log("networkConnection.receiveNextMessage: no data in multipart file message", type: .error)
                        break
                    }
                    do {
                        let messageInfo = try data.extractObject(from: 0..<Int(migratorMessage.migratorMessageInfoLenght), ofType: FileMessage.self)
                        self.onBytesReceived.send(data.count)
                        shouldAutoReceiveNext = false
                        let chunkData = data
                        Task.detached(priority: .utility) { [weak self] in
                            guard let self else { return }
                            do {
                                try self.writeReceivedFileChunk(chunkData, messageInfo: messageInfo)
                            } catch {
                                self.logger.log("networkConnection.receiveNextMessage: failed to write chunk of data -> \"\(error.localizedDescription)\" on \(messageInfo.source.fullURL().absoluteString)", type: .error)
                            }
                            DispatchQueue.main.async {
                                self.receiveNextMessage()
                            }
                        }
                    } catch let error {
                        self.logger.log("networkConnection.receiveNextMessage: failed to write chunk of data -> \"\(error)\"", type: .error)
                    }
                case .defaults:
                    self.logger.log("networkConnection.receiveNextMessage: defaults message received", type: .default)
                    do {
                        if var data = content {
                            let messageInfo = try data.extractObject(from: 0..<Int(migratorMessage.migratorMessageInfoLenght), ofType: DefaultsMessage.self)
                            if let boolValue = messageInfo.boolValue {
                                UserDefaults.standard.setValue(boolValue, forKey: messageInfo.key)
                            } else if let stringValue = messageInfo.stringValue {
                                UserDefaults.standard.setValue(stringValue, forKey: messageInfo.key)
                            }
                        }
                    } catch let error {
                        self.logger.log("networkConnection.receiveNextMessage: failed to save UserDefaults value -> \"\(error.localizedDescription)\"", type: .error)
                    }
                case .preferences:
                    self.logger.log("networkConnection.receiveNextMessage: preferences message received")
                    do {
                        if var data = content {
                            let messageInfo = try data.extractObject(from: 0..<Int(migratorMessage.migratorMessageInfoLenght), ofType: PreferencesMessage.self)
                            self.onBytesReceived.send(data.count)
                            let domain = PreferenceDomain(applicationID: messageInfo.applicationID, isByHost: messageInfo.isByHost, keyFilter: .all)
                            self.logger.log("networkConnection.receiveNextMessage: applying domain \"\(messageInfo.applicationID ?? "global")\" for group \"\(messageInfo.groupID)\"")
#if !DEBUG
                            try PreferencesDiscovery.apply(data, to: domain)
#endif
                        }
                    } catch let error {
                        self.logger.log("networkConnection.receiveNextMessage: failed to apply preferences -> \"\(error.localizedDescription)\"", type: .error)
                    }
                case .deviceInfo:
                    self.logger.log("networkConnection.receiveNextMessage: device info message received", type: .default)
                    do {
                        if var data = content {
                            let deviceInfo = try data.extractObject(from: 0..<Int(migratorMessage.migratorMessageInfoLenght), ofType: DeviceInfoMessage.self)
                            self.logger.log("networkConnection.receiveNextMessage: device architecture: \(deviceInfo.architecture), OS: \(deviceInfo.osVersion)")
                            self.onDeviceInfoReceived.send(deviceInfo)
                        }
                    } catch let error {
                        self.logger.log("networkConnection.receiveNextMessage: failed to decode device info -> \"\(error.localizedDescription)\"", type: .error)
                    }
                }
            }
            }
        }
    }

    /// Writes a fully-received single-part file to disk. Run off the connection's queue (see
    /// the `.file` case in `receiveNextMessage()`) so a slow or stalled destination volume can't
    /// block the queue Network.framework uses to deliver connection state/keepalive events.
    nonisolated private func writeReceivedFile(_ data: Data, messageInfo: FileMessage) throws {
        let fileURL = try validatedDestination(for: messageInfo)
        let directory = fileURL.deletingLastPathComponent()
        let attributes = messageInfo.sanitizedAttributes
#if !DEBUG
        if FileManager.default.fileExists(atPath: fileURL.path) {
            switch AppContext.duplicateFilesHandlingPolicy {
            case .ignore:
                break
            case .move:
                if !FileManager.default.fileExists(atPath: "\(AppContext.backupPath)/\(directory.path)") {
                    try? FileManager.default.createDirectory(atPath: "\(AppContext.backupPath)/\(directory.path)", withIntermediateDirectories: true)
                }
                try? FileManager.default.moveItem(atPath: fileURL.path, toPath: "\(AppContext.backupPath)/\(fileURL.path)")
                fallthrough
            case .overwrite:
                // Git pack/index files and the like are read-only; replacing one would otherwise fail.
                makeOwnerWritableIfNeeded(atPath: fileURL.path)
                guard FileManager.default.createFile(atPath: fileURL.path, contents: data, attributes: attributes) else {
                    logger.log("networkConnection.writeReceivedFile: failed to create file \"\(fileURL.path)\"", type: .error)
                    throw MigratorError.fileError(type: .failedToWriteFile)
                }
            }
        } else {
            try FileManager.default.createDirectory(atPath: directory.path, withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: fileURL.path, contents: data, attributes: attributes) else {
                logger.log("networkConnection.writeReceivedFile: failed to create file \"\(fileURL.path)\"", type: .error)
                throw MigratorError.fileError(type: .failedToWriteFile)
            }
        }
#endif
    }

    /// Gives the owner write access to an existing file that lacks it (mode 0444, as git uses for
    /// `*.pack`/`*.idx` and loose objects) so it can be rewritten. The source mode is applied again
    /// once the data has been written.
    nonisolated private func makeOwnerWritableIfNeeded(atPath path: String) {
        guard let current = (try? FileManager.default.attributesOfItem(atPath: path))?[.posixPermissions] as? NSNumber,
              current.intValue & 0o200 == 0 else { return }
        try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: current.intValue | 0o200)],
                                               ofItemAtPath: path)
    }

    /// Resolves where a peer-supplied file message may be written, logging and reporting a
    /// rejection before rethrowing as a file error.
    nonisolated private func validatedDestination(for messageInfo: FileMessage) throws -> URL {
        do {
            return try messageInfo.source.validatedReceiveURL()
        } catch {
            logger.log("networkConnection.validatedDestination: rejected \"\(messageInfo.source.relativePath)\": \(error.localizedDescription)", type: .error)
            let rejectedPath = messageInfo.source.relativePath
            Task { @MainActor in
                MigrationReportController.shared.addError("Rejected unsafe file path: \(rejectedPath)")
            }
            throw MigratorError.fileError(type: .failedToWriteFile)
        }
    }

    /// Appends one chunk of a multipart file to disk. Run off the connection's queue (see the
    /// `.multipartFile` case in `receiveNextMessage()`) for the same reason as `writeReceivedFile`.
    /// Chunk ordering is preserved by `receiveNextMessage()` only re-arming the next receive once
    /// this call returns, so chunks are still written strictly in order, just off the main queue.
    nonisolated private func writeReceivedFileChunk(_ data: Data, messageInfo: FileMessage) throws {
        let fileURL = try validatedDestination(for: messageInfo)
        let directory = fileURL.deletingLastPathComponent()
        let attributes = messageInfo.sanitizedAttributes
#if !DEBUG
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(atPath: directory.path, withIntermediateDirectories: true)
        }
        // A source file can be read-only (0444). Its mode is applied after every chunk below, so
        // from the second chunk on - or when re-sending over an earlier attempt - the file would
        // refuse to be opened for writing. Re-open it to the owner for the duration of the write.
        makeOwnerWritableIfNeeded(atPath: fileURL.path)
        if !FileManager.default.fileExists(atPath: fileURL.path) || messageInfo.partNumber == 0 {
            // Create the file owner-writable even if the source is read-only (0444, e.g. git packs),
            // otherwise it can't be opened for writing right below. The source mode is applied after
            // every chunk, further down.
            var creationAttributes = attributes
            if let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue {
                creationAttributes[.posixPermissions] = NSNumber(value: permissions | 0o200)
            }
            FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: creationAttributes)
        }
        guard let fileHandle = FileHandle(forWritingAtPath: fileURL.path) else {
            let mode = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.posixPermissions] as? NSNumber
            let parentMode = (try? FileManager.default.attributesOfItem(atPath: directory.path))?[.posixPermissions] as? NSNumber
            logger.log("networkConnection.writeReceivedFileChunk: cannot open \"\(fileURL.path)\" for writing (file mode \(mode.map { String($0.intValue, radix: 8) } ?? "missing"), parent mode \(parentMode.map { String($0.intValue, radix: 8) } ?? "missing"))", type: .error)
            throw MigratorError.fileError(type: .failedDuringFileHandling())
        }
        defer {
            try? fileHandle.close()
        }
        if let byteOffset = messageInfo.byteOffset {
            // Write at the chunk's exact position so a re-sent chunk overwrites itself.
            try fileHandle.seek(toOffset: byteOffset)
        } else {
            try fileHandle.seekToEnd()
        }
        try fileHandle.write(contentsOf: data)
        do {
            try FileManager.default.setAttributes(attributes, ofItemAtPath: fileURL.path)
        } catch {
            logger.log("networkConnection.writeReceivedFileChunk: failed to set attributes -> \"\(error.localizedDescription)\"", type: .error)
        }
#endif
    }
}
//  swiftlint:enable function_body_length type_body_length file_length
