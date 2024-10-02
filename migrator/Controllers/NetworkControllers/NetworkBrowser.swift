//
//  NetworkBrowser.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 15/11/2023.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import Network
import Combine

/// Manages the discovery of network services using NWBrowser. It provides functionality to start and stop the discovery process and publishes updates on the browser's state and discovered services.
final class NetworkBrowser {

    // MARK: - Published Properties
    
    /// Publishes updates on the state of the NWBrowser instance.
    let onNewBrowserState = PassthroughSubject<NWBrowser.State, Never>()
    /// Publishes changes in the discovered network services.
    let onNewBrowserResults = PassthroughSubject<Set<NWBrowser.Result.Change>, Never>()
    
    // MARK: - Private Variables
    
    /// The NWBrowser instance used for discovering network services.
    private var browser: NWBrowser
    
    // MARK: - Private Constants
    
    /// Logger instance.
    private let logger: MLogger = MLogger.main

    // MARK: - Initializer
    
    /// Initializes a new NetworkBrowser instance configured for discovering Bonjour services.
    init() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        // Configures the browser for discovering services with the specified Bonjour type and domain.
        browser = NWBrowser(for: .bonjour(type: AppContext.networkServiceIdentifier, domain: nil), using: parameters)
    }

    // MARK: - Public Methods
    
    /// Starts the discovery process of network services.
    func start() {
        // Sets up handlers to publish state updates and discovered services changes.
        browser.stateUpdateHandler = { [weak self] newState in
            self?.onNewBrowserState.send(newState)
        }
        browser.browseResultsChangedHandler = { [weak self] _, changes in
            self?.onNewBrowserResults.send(changes)
        }
        // Starts the NWBrowser instance on the main queue.
        browser.start(queue: .main)
    }
    
    /// Stops the discovery process and resets the NWBrowser instance.
    func stop() {
        // Cancels the current browsing session.
        browser.cancel()
        // Reinitializes the browser to be ready for a new discovery session.
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        browser = NWBrowser(for: .bonjour(type: "_migrator._tcp", domain: nil), using: parameters)
    }
}
