//
//  NWInterface-Extension.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 09/12/2025.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Network

extension NWInterface.InterfaceType {
    var stringValue: String {
        switch self {
        case .other: return "other"
        case .wifi: return "wifi"
        case .wiredEthernet: return "wiredEthernet"
        case .loopback: return "loopback"
        case .cellular: return "cellular"
        @unknown default: return "unknown"
        }
    }
}
