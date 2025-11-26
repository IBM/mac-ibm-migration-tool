//
//  ConfigProfileSection.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 26/04/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// This struct represent a section of the configuration profiles installed on the device.
struct ConfigProfileSection: Decodable {
    
    // MARK: - Constants
    
    let name: String?
    let profiles: [ConfigProfile]
    
    // MARK: - Private Enums
    
    private enum CodingKeys: String, CodingKey {
        case name = "_name"
        case profiles = "_items"
    }
}
