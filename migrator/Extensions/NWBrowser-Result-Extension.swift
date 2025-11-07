//
//  NWBrowser-Result-Extension.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 15/11/2023.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import Network

extension NWBrowser.Result: @retroactive Identifiable {
    /// Provides a unique identifier for each NWBrowser.Result instance.
    public var id: Int {
        return self.hashValue
    }
    
    /// A computed property to derive a user-friendly name for the NWBrowser.Result.
    public var resultName: String {
        switch self.endpoint {
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
    }
}
