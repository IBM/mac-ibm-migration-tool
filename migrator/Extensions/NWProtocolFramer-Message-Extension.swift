//
//  NWProtocolFramer-Message-Extension.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 30/01/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import Network

extension NWProtocolFramer.Message {
    /// A computed property to get the type of migration message from the message metadata.
    var migratorMessageType: MigratorMessageType {
        if let type = self["MigratorMessageType"] as? MigratorMessageType {
            return type
        } else {
            return .invalid
        }
    }
    
    /// A computed property to get the length of additional information included in the migration message.
    var migratorMessageInfoLenght: UInt32 {
        if let infoLenght = self["MigratorMessageInfoLenght"] as? UInt32 {
            return infoLenght
        } else {
            return 0
        }
    }
    
    /// Initializes a new `NWProtocolFramer.Message` with custom migration message type and information length.
    /// - Parameters:
    ///   - migratorMessageType: The type of migration message.
    ///   - infoLenght: The length of additional information included in the message.
    convenience init(migratorMessageType: MigratorMessageType, infoLenght: UInt32) {
        self.init(definition: MigratorNetworkProtocol.definition)
        self["MigratorMessageType"] = migratorMessageType
        self["MigratorMessageInfoLenght"] = infoLenght
    }
}
