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
final class DeviceManagementHelper {
    
    // MARK: - Static Constants
    
    static let shared = DeviceManagementHelper()
    
    // MARK: - Variables
    
    private(set) var state: DeviceManagementState = .unknown
    
    /// Determine if possible to run Jamf Inventory Update based on the current device MDM environment state.
    var isJamfReconAvailable: Bool {
        switch state {
        case .managed:
            return !AppContext.shouldSkipJamfRecon
        default:
            return false
        }
    }
    
    // MARK: - Initializer
    
    private init() {
        loadDeviceManagementState()
    }
    
    // MARK: - Private Methods
    
    /// Loads the current device management state by analyzing profiles.
    private func loadDeviceManagementState() {
        fetchProfiles { [weak self] profiles in
            guard let self = self else { return }
            
            guard !profiles.isEmpty else {
                self.state = .unmanaged
                return
            }
            
            if let managementProfile = self.findManagementProfile(in: profiles) {
                self.state = self.determineState(for: managementProfile)
            } else {
                self.state = .unmanaged
            }
        }
    }
    
    /// Executes the system command to fetch configuration profiles and parses the result.
    private func fetchProfiles(completion: @escaping ([ConfigProfile]) -> Void) {
        let command = "system_profiler -json SPConfigurationProfileDataType"
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/zsh"
        task.launch()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        do {
            let dataType = try ConfigurationProfileDataType(from: output.replacingOccurrences(of: "\n", with: ""))
            let profiles = dataType.sections.first(where: { $0.name == "spconfigprofile_section_deviceconfigprofiles" })?.profiles ?? []
            completion(profiles)
        } catch {
            completion([])
        }
    }
    
    /// Finds the management profile containing the `com.apple.mdm` payload.
    private func findManagementProfile(in profiles: [ConfigProfile]) -> ConfigProfile? {
        profiles.first { profile in
            profile.payloads?.contains { $0.name == "com.apple.mdm" } ?? false
        }
    }
    
    /// Determines the device management state based on the management profile.
    private func determineState(for managementProfile: ConfigProfile) -> DeviceManagementState {
        if #available(macOS 13.0, *) {
            guard let serverURLString = managementProfile.payloads?.first(where: { $0.name == "com.apple.mdm" })?.serverURL,
                  let serverURL = URL(string: serverURLString)?.host() else {
                return .managedByUnknownOrg
            }
            for environment in AppContext.mdmEnvironments {
                guard let environmentURL = URL(string: environment.serverURL)?.host(), environmentURL == serverURL else { continue }
                return .managed(env: environment)
            }
        } else {
            guard let serverURLString = managementProfile.payloads?.first(where: { $0.name == "com.apple.mdm" })?.serverURL,
                  let serverURL = URL(string: serverURLString)?.host else {
                return .managedByUnknownOrg
            }
            for environment in AppContext.mdmEnvironments {
                guard let environmentURL = URL(string: environment.serverURL)?.host, environmentURL == serverURL else { continue }
                return .managed(env: environment)
            }
        }
        
        return .managedByUnknownOrg
    }
}
