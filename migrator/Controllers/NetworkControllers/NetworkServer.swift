//
//  NetworkServer.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 14/11/2023.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import Network
import Combine

/// Manages a network listener for discovering and accepting connections from network clients.
/// This class specifically listens for Bonjour services of type "_migrator._tcp".
final class NetworkServer {
    
    // MARK: - Published Properties
    
    /// Publishes new connections established with the network service.
    let onNewConnection = PassthroughSubject<NWConnection, Never>()
    /// Publishes updates on the listener's state to track its lifecycle and status.
    let onNewListenerState = PassthroughSubject<NWListener.State, Never>()
    
    // MARK: - Private Variables
    
    /// The network listener responsible for accepting incoming network connections.
    private var listener: NWListener?
    
    // MARK: - Private Constants
    
    /// Logger instance.
    private let logger: MLogger = MLogger.main
        
    // MARK: - Lifecycle Methods
    
    /// Starts the network listener to make the device discoverable as a service of type "_migrator._tcp".
    /// The listener will only accept connections that provide a matching passcode.
    /// - Parameter passcode: A passcode required for clients to connect to this service.
    func start(withPasscode passcode: String) throws {
        let parameters = NWParameters(passcode: passcode)
        listener = try NWListener(using: parameters)
        listener?.service = NWListener.Service(type: AppContext.networkServiceIdentifier+"._tcp")
        // Handler for listener state updates.
        listener?.stateUpdateHandler = { [weak self] newState in
            self?.onNewListenerState.send(newState)
        }
        
        // Handler for establishing new connections.
        listener?.newConnectionHandler = { [weak self] newConnection in
            self?.onNewConnection.send(newConnection)
        }
        
        listener?.start(queue: .main)
    }
    
    /// Stops the currently running network listener.
    func stop() {
        listener?.cancel()
        listener = nil
    }
}
