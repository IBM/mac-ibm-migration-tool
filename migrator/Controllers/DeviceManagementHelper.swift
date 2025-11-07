//
//  DeviceManagementHelper.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 04/09/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// Helper class used to run the device management state discovery.
final class DeviceManagementHelper {
    
    // MARK: - Static Constants
    
    static let shared = DeviceManagementHelper()
    
    // MARK: - Private Variables
    
    private(set) var state: DeviceManagementState?
    private var knownEnvs: [ManagedEnvironment]?
    
    /// Determine if possible to run Jamf Inventory Update based on the current device MDM environment state.
    var isJamfReconAvailable: Bool {
        switch state {
        case .managed:
            return !AppContext.shouldSkipJamfRecon
        default:
            return false
        }
    }
    
    init() {
        loadDeviceManagementState(with: AppContext.mdmEnvironments)
    }

    // MARK: - Public Methods
    
    /// Checks if the given profile is already installed on the device.
    private func loadDeviceManagementState(with knownEnvsArray: [ManagedEnvironment] = []) {
        if !knownEnvsArray.isEmpty {
            self.knownEnvs = knownEnvsArray
        }
        
        fetchProfiles { [weak self] profiles in
            guard let self = self else { return }
            
            guard !profiles.isEmpty else {
                self.state = .unmanaged
                MLogger.main.log("deviceManagementHelper:loadDeviceManagementState no matching management profile found.", type: .default)
                return
            }
            
            if let (managementProfile, payload) = self.findManagementProfile(in: profiles) {
                self.handleManagementProfile(managementProfile: managementProfile, payload: payload, completion: { state in
                    self.state = state
                })
            } else {
                self.state = .unmanaged
                MLogger.main.log("deviceManagementHelper:loadDeviceManagementState no matching management profile found.", type: .default)
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Executes the command to fetch profiles and parses the result.
    private func fetchProfiles(completion: @escaping ([ConfigProfile]) -> Void) {
        MLogger.main.log("deviceManagementHelper:fetchProfiles fecthing installed profiles...", type: .default)
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
            MLogger.main.log("deviceManagementHelper:fetchProfiles successfully retrieved and parsed \(profiles.count) installed profiles.", type: .default)
            completion(profiles)
        } catch {
            MLogger.main.log("deviceManagementHelper:fetchProfiles failed to fecth installed profiles with error: \(error.localizedDescription), result of the command: \(output)", type: .error)
            completion([])
        }
    }
    
    /// Finds the management profile with `com.apple.mdm` payload.
    private func findManagementProfile(in profiles: [ConfigProfile]) -> (ConfigProfile, ConfigProfilePayload)? {
        profiles.first { profile in
            profile.payloads?.contains { $0.name == "com.apple.mdm" } ?? false
        }.flatMap { profile in
            guard let payload = profile.payloads?.first(where: { $0.name == "com.apple.mdm" }) else { return nil }
            return (profile, payload)
        }
    }
    
    /// Handles the logic for managing a profile.
    private func handleManagementProfile(managementProfile: ConfigProfile,
                                         payload: ConfigProfilePayload,
                                         completion: @escaping (DeviceManagementState) -> Void) {
        if let env = findMatchingEnvironment(for: payload.serverURL) {
            MLogger.main.log("deviceManagementHelper:loadDeviceManagementState found matching management profile.", type: .default)
            completion(.managed(env: env))
        } else {
            MLogger.main.log("deviceManagementHelper:loadDeviceManagementState found unknown management profile.", type: .default)
            completion(.managedByUnknownOrg)
        }
    }
    
    /// Finds a matching enviroment and environment for the given server URL.
    private func findMatchingEnvironment(for serverURL: String?) -> ManagedEnvironment? {
        guard let serverURLString = serverURL, let serverURL = URL(string: serverURLString) else { return nil }
        for environment in knownEnvs ?? [] {
            guard let envServerURL = URL(string: environment.serverURL) else { continue }
            if #available(macOS 13.0, *) {
                guard envServerURL.host() == serverURL.host() else { continue }
            } else {
                guard envServerURL.host == serverURL.host else { continue }
            }
            return environment
        }
        return nil
    }
}
