//
//  ManagedEnvironment.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 04/09/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// This struct represents a MDM environment.
struct ManagedEnvironment: Codable {
    
    // MARK: - Variables
    
    var name: String
    var serverURL: String
    var reconPolicyID: String
}
