//
//  DeviceManagementState.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 26/04/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// Enum that represents the possible device management states.
enum DeviceManagementState {
    case unmanaged
    case managed(env: ManagedEnvironment)
    case managedByUnknownOrg
    case unknown
}
