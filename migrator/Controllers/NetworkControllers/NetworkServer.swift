//
//  NetworkServer.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 14/11/2023.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Network
import Combine

/// Manages a network listener for discovering and accepting connections from network clients.
/// This class specifically listens for Bonjour services of type "_migrator._tcp".
@MainActor
final class NetworkServer {
    
    // MARK: - Published Properties
    
    /// Publishes new connections established with the network service.
    let onNewConnection = PassthroughSubject<NWConnection, Never>()
    /// Publishes updates on the listener's state to track its lifecycle and status.
    let onNewListenerState = PassthroughSubject<NWListener.State, Never>()
    /// Publishes updates on the service registration state to track if the service is advertised on the network.
    let onServiceRegistrationUpdate = PassthroughSubject<NWListener.ServiceRegistrationChange, Never>()
    
    // MARK: - Private Variables
    
    /// The network listener responsible for accepting incoming network connections.
    private var listener: NWListener?
    
    // MARK: - Private Constants
    
    /// Logger instance.
    private let logger = MLogger.main.scoped(to: .network)
        
    // MARK: - Lifecycle Methods
    
    /// Starts the network listener to make the device discoverable as a service of type "_migrator._tcp".
    /// TLS 1.3 only provides confidentiality here via an ephemeral, in-memory server identity;
    /// the pairing code is checked afterwards at the application layer (see `PairingAuthenticator`),
    /// so callers still need to pass the passcode to each `NetworkConnection` built from
    /// `onNewConnection`.
    func start() throws {
        logger.log("networkServer.start: generating ephemeral TLS identity and starting listener for service \"\(AppContext.networkServiceIdentifier)._tcp\"", type: .default)
        let identity = try EphemeralTLSIdentity.makeIdentity()
        let parameters = NWParameters(tlsIdentity: identity)
        listener = try NWListener(using: parameters)
        listener?.service = NWListener.Service(type: AppContext.networkServiceIdentifier+"._tcp")
        // `NWListener`'s handlers aren't `@MainActor`-annotated, but every handler below is
        // started on the `.main` queue, so they always fire there.
        // Handler for listener state updates.
        listener?.stateUpdateHandler = { [weak self] newState in
            MainActor.assumeIsolated {
                switch newState {
                case .ready:
                    self?.logger.log("networkServer.stateUpdateHandler: listener ready, advertising service", type: .default)
                case .failed(let error):
                    self?.logger.log("networkServer.stateUpdateHandler: listener failed -> \"\(error.localizedDescription)\"", type: .error)
                case .cancelled:
                    self?.logger.log("networkServer.stateUpdateHandler: listener cancelled", type: .default)
                default:
                    break
                }
                self?.onNewListenerState.send(newState)
            }
        }

        // Handler for establishing new connections.
        listener?.newConnectionHandler = { [weak self] newConnection in
            MainActor.assumeIsolated {
                self?.logger.log("networkServer.newConnectionHandler: accepted incoming connection from \"\(newConnection.endpoint.debugDescription)\"", type: .default)
                self?.onNewConnection.send(newConnection)
            }
        }

        // Handler for service registration updates.
        listener?.serviceRegistrationUpdateHandler = { [weak self] change in
            MainActor.assumeIsolated {
                switch change {
                case .add(let endpoint):
                    self?.logger.log("networkServer.serviceRegistrationUpdateHandler: service registered as \"\(endpoint.debugDescription)\"", type: .default)
                case .remove(let endpoint):
                    self?.logger.log("networkServer.serviceRegistrationUpdateHandler: service unregistered -> \"\(endpoint.debugDescription)\"", type: .error)
                @unknown default:
                    break
                }
                self?.onServiceRegistrationUpdate.send(change)
            }
        }

        listener?.start(queue: .main)
    }

    /// Stops the currently running network listener.
    func stop() {
        logger.log("networkServer.stop: stopping listener", type: .default)
        listener?.cancel()
        listener = nil
    }
}
