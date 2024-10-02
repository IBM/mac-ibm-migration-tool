//
//  CommunicationInterfaces.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 30/01/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// Enumerates the types of communication interfaces a device may support.
enum CommunicationInterfaces: CaseIterable {
    case wifi
    case thunderbolt
    case cellular
}
