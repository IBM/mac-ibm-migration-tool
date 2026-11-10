//
//  JamfReconManager.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 04/09/2024.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// The JamfReconManager actor is designed to manage and monitor the execution of a specific Jamf policy,
/// particularly related to inventory updates (recon), using AppleScript to interact with system processes.
actor JamfReconManager {

    // MARK: - Constants
    
    /// Logger instance for logging events and messages
    let logger = MLogger.main.scoped(to: .device)
    
    // MARK: - Computed Variables
    
    /// The ID of the Jamf policy used for the recon (inventory update)
    var reconPolicyID: String {
        get async {
            switch await DeviceManagementHelper.shared.state {
            case .managed(env: let env):
                return env.reconPolicyID ?? "null"
            default:
                return ""
            }
        }
    }
    
    /// Checks if the Self Service application is currently running
    var isSelfServiceRunning: Bool {
        if let appleEventDescriptor = NSAppleScript(source: "do shell script \"ps aux | grep '[S]elf Service'\"")?.executeAndReturnError(nil),
           let output = appleEventDescriptor.stringValue {
            return output.contains("Self Service")
        }
        return false
    }
    
    /// Checks if the Jamf recon (inventory update) process is currently running
    var isReconRunning: Bool {
        if let appleEventDescriptor = NSAppleScript(source: "do shell script \"ps aux | grep '[j]amf'\"")?.executeAndReturnError(nil),
           let output = appleEventDescriptor.stringValue {
            return output.contains("jamf recon")
        }
        return false
    }
    
    /// Checks if any Jamf policies are currently running
    var areJamfPoliciesRunning: Bool {
        if let appleEventDescriptor = NSAppleScript(source: "do shell script \"ps aux | grep '[j]amf'\"")?.executeAndReturnError(nil),
           let output = appleEventDescriptor.stringValue {
            return output.contains("jamf policy")
        }
        return false
    }
    
    // MARK: - Public Methods
    
    /// Silently launches the Self Service application without bringing it to the foreground
    func silentlyRunSelfService() {
        logger.log("jamfReconManager.silentlyRunSelfService: silently starting Self Service", type: .default)
        do {
            try runOpen(arguments: ["-j", AppContext.storePath])
        } catch {
            logger.log("jamfReconManager.silentlyRunSelfService: failed to start Self Service -> \"\(error.localizedDescription)\"", type: .error)
        }
    }

    /// Runs `/usr/bin/open` with an argument vector, so no value is ever parsed by a shell.
    private func runOpen(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        try process.run()
    }

    /// Opens the Self Service URL that executes the policy with the given ID, in the background.
    private func openPolicyURL(policyID: String) throws {
        try runOpen(arguments: ["-g", "jamfselfservice://content?entity=policy&id=\(policyID)&action=execute"])
    }

    /// Asynchronously queues and starts the Jamf recon policy, then waits for it to begin running
    func queueReconPolicy() async {
        let policyID = await reconPolicyID
        logger.log("jamfReconManager.queueReconPolicy: queueing Jamf Inventory Update policy \"\(policyID)\"", type: .default)
        do {
            try openPolicyURL(policyID: policyID)
        } catch {
            logger.log("jamfReconManager.queueReconPolicy: failed to open Self Service policy URL -> \"\(error.localizedDescription)\"", type: .error)
        }
        await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                sleep(10)
                while await !self.isReconRunning {
                    sleep(2)
                }
                continuation.resume()
            }
        }
        logger.log("jamfReconManager.queueReconPolicy: Jamf Inventory Update policy is now running", type: .default)
    }

    /// Immediately runs the Jamf recon policy without waiting for its execution
    func runReconPolicy() async {
        let policyID = await reconPolicyID
        logger.log("jamfReconManager.runReconPolicy: running Jamf Inventory Update policy \"\(policyID)\"", type: .default)
        do {
            try openPolicyURL(policyID: policyID)
        } catch {
            logger.log("jamfReconManager.runReconPolicy: failed to open Self Service policy URL -> \"\(error.localizedDescription)\"", type: .error)
        }
    }

    /// Asynchronously waits for the completion of the Jamf recon process
    func waitForReconCompletion() async {
        logger.log("jamfReconManager.waitForReconCompletion: waiting for the Jamf Inventory Update to complete", type: .default)
        await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                sleep(10)
                while await self.isReconRunning {
                    sleep(2)
                }
                continuation.resume()
            }
        }
        logger.log("jamfReconManager.waitForReconCompletion: Jamf Inventory Update completed", type: .default)
    }

    /// Kills the Self Service application if it is currently running
    func killSelfService() {
        logger.log("jamfReconManager.killSelfService: closing Self Service", type: .default)
        var errors: NSDictionary?
        _ = NSAppleScript(source: "do shell script \"killall 'Self Service'\"")?.executeAndReturnError(&errors)
        if let errors {
            // `killall` returns a non-zero exit status (surfaced here as an AppleScript error) when
            // no matching process is found, which is an expected outcome if Self Service already
            // quit on its own - so this is informational rather than a genuine failure.
            logger.log("jamfReconManager.killSelfService: Self Service was not running or could not be closed -> \"\(errors)\"", type: .default)
        }
    }
}
