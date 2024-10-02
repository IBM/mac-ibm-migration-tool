//
//  DeviceListRow.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 05/01/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// Struct representing a row in a device list view
struct DeviceListRow: View {
    
    // MARK: - Constants
    
    /// Network device model associated with this row
    let result: Binding<NetworkDevice>
    
    // MARK: - Views
    
    /// Body of the view
    var body: some View {
        HStack {
            Text(result.name.wrappedValue)
            Spacer()
            if result.interfaces.contains(where: { $0.wrappedValue == .thunderbolt }) {
                Image(systemName:  "cable.connector.horizontal")
                    .resizable()
                    .frame(width: 19, height: 9)
            } else if result.interfaces.contains(where: { $0.wrappedValue == .wifi }) {
                Image(systemName:  "wifi.circle")
                    .resizable()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName:  "antenna.radiowaves.left.and.right.circle")
                    .resizable()
                    .frame(width: 18, height: 18)
            }
        }
    }
}
