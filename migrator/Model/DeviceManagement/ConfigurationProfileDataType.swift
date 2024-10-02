//
//  ConfigurationProfileDataType.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 26/04/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// This struct describe the system profiles Configuration Profile Data Type.
struct ConfigurationProfileDataType: Decodable {
    
    // MARK: - Constants
    
    let sections: [ConfigProfileSection]
    
    // MARK: - Private Enums
    
    private enum CodingKeys: String, CodingKey {
        case sections = "SPConfigurationProfileDataType"
    }
}
