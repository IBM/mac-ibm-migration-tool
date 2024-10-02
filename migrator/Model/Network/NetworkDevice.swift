//
//  NetworkDevice.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 16/11/2023.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import Network

/// Represents a network device discovered by `NWBrowser`.
struct NetworkDevice {
    
    // MARK: - Variables
    
    /// The raw browser result containing detailed information about the network service.
    var browserResult: NWBrowser.Result
    /// List of communication interfaces supported by the device, filtered and mapped from the browser result.
    var interfaces: [CommunicationInterfaces]
    /// Human-readable name for the device, determined based on the type of endpoint in the browser result.
    var name: String
    /// Unique identifier derived from the browser result, ensuring each device is uniquely identifiable.
    var id: Int {
        return browserResult.id
    }
    
    // MARK: - Initializers
    
    /// Initializes a new `NetworkDevice` from a `NWBrowser.Result`.
    /// - Parameter browserResult: The result from a network browser used to discover the device.
    init(browserResult: NWBrowser.Result) {
        self.browserResult = browserResult
        
        // Determines the device name based on the endpoint type, defaulting to "Unknown" for unrecognized types.
        self.name = {
            switch browserResult.endpoint {
            case .hostPort:
                return "Unknown"
            case .service(name: let name, _, _, _):
                return name
            case .unix:
                return "Unknown"
            case .url:
                return "Unknown"
            case .opaque:
                return "Unknown"
            @unknown default:
                return "Unknown"
            }
        }()
        
        // Maps the interfaces reported by the browser result to a predefined list of `CommunicationInterfaces`.
        let mappedInterfaces: [CommunicationInterfaces] = browserResult.interfaces.compactMap { interface in
            switch interface.type {
            case .other:
                return nil
            case .wifi:
                return CommunicationInterfaces.wifi
            case .cellular:
                return CommunicationInterfaces.cellular
            case .wiredEthernet:
                return CommunicationInterfaces.thunderbolt
            case .loopback:
                return nil
            @unknown default:
                return nil
            }
        }
        
        // Removes duplicates and sorts the interfaces for consistent ordering.
        self.interfaces = Set<CommunicationInterfaces>(mappedInterfaces).sorted(by: ==)
    }
}

extension NetworkDevice: Identifiable, Hashable {
    
    // MARK: - Conformance to `Equatable`
    
    static func == (lhs: NetworkDevice, rhs: NetworkDevice) -> Bool {
        return lhs.id == rhs.id
    }
    
    // MARK: - Conformance to `Hashable`
    
    /// Provides a hash value for the object, allowing it to be used in hash-based collections.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
