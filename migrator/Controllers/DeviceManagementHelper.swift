//
//  DeviceManagementHelper.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 04/09/2024.
//  © Copyright IBM Corp. 2023, 2026
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
        
        fetchProfiles { [weak self] serverURL in
            guard let self = self else { return }
            
            guard let serverURL = serverURL else {
                self.state = .unmanaged
                MLogger.main.log("deviceManagementHelper:loadDeviceManagementState no matching management profile found.", type: .default)
                return
            }
            
            self.handleServerURL(url: serverURL, completion: { state in
                self.state = state
            })
        }
    }
    
    // MARK: - Private Methods
    
    /// Executes the command to fetch profiles and parses the result.
    private func fetchProfiles(completion: @escaping (String?) -> Void) {
        MLogger.main.log("deviceManagementHelper:fetchProfiles fecthing installed profiles...", type: .default)
        let command = "profiles status -type enrollment | grep \"MDM server\" | awk -F': ' '{print $2}'"
        let task = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = errorPipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/sh"
        task.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
        ]
        
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        // Extract only the last non-empty line which should contain the serverURL
        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        guard let serverURL = lines.last, !serverURL.isEmpty else {
            MLogger.main.log("deviceManagementHelper:fetchProfiles device appear not to be managed. No Server URL found. Result of the command: \(output)", type: .error)
            completion(nil)
            return
        }
        
        MLogger.main.log("deviceManagementHelper:fetchProfiles successfully retrieved and parsed Server URL: \(serverURL)", type: .default)
        completion(serverURL)
    }
    
    /// Handles the logic for managing a profile.
    private func handleServerURL(url: String,
                                 completion: @escaping (DeviceManagementState) -> Void) {
        if let env = findMatchingEnvironment(for: url) {
            MLogger.main.log("deviceManagementHelper:loadDeviceManagementState found matching management profile.", type: .default)
            completion(.managed(env: env))
        } else {
            MLogger.main.log("deviceManagementHelper:loadDeviceManagementState found unknown management profile.", type: .default)
            completion(.managedByUnknownOrg)
        }
    }
    
    /// Finds a matching enviroment and environment for the given server URL.
    private func findMatchingEnvironment(for serverURLString: String) -> ManagedEnvironment? {
        guard let serverURL = URL(string: serverURLString) else { return nil }
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
