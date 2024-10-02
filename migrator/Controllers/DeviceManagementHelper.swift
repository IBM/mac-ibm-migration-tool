//
//  DeviceManagementHelper.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 04/09/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// Helper class used to run the device management state discovery.
class DeviceManagementHelper {
    
    // MARK: - Static Constants
    
    static let shared = DeviceManagementHelper()

    // MARK: - Variables
    
    var state: DeviceManagementState
    
    /// Determine if possible to run Jamf Inventory Update based on the current device MDM environment state.
    var isJamfReconAvailable: Bool {
        switch state {
        case .managed:
            return true && !AppContext.shouldSkipJamfRecon
        default:
            return false
        }
    }
        
    // MARK: - Initializers
    
    init() {
        let command = "system_profiler -json SPConfigurationProfileDataType"
        var profiles: [ConfigProfile] = []
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/zsh"
        task.standardInput = nil
        task.launch()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)!
        do {
            let dataType = try ConfigurationProfileDataType(from: output.replacingOccurrences(of: "\n", with: ""))
            profiles = dataType.sections.first(where: { $0.name == "spconfigprofile_section_deviceconfigprofiles" })?.profiles ?? []
            guard !profiles.isEmpty else {
                state = .unmanaged
                return
            }
            if let managementProfile = profiles.first(where: { $0.payloads?.contains(where: { $0.name == "com.apple.mdm" }) ?? false }) {
                if let serverURL = managementProfile.payloads?.first(where: { $0.name == "com.apple.mdm" })?.serverURL,
                   let environment = AppContext.mdmEnvironments.first(where: { $0.serverURL == serverURL }) {
                    state = .managed(env: environment)
                } else {
                    state = .managedByUnknownOrg
                }
            } else {
                state = .unmanaged
            }
        } catch {
            state = .unknown
        }
    }
}
