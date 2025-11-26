//
//  JamfReconManager.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 04/09/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// The JamfReconManager actor is designed to manage and monitor the execution of a specific Jamf policy,
/// particularly related to inventory updates (recon), using AppleScript to interact with system processes.
actor JamfReconManager {
    
    // MARK: - Constants
    
    /// Logger instance for logging events and messages
    let logger = MLogger.main
    
    // MARK: - Computed Variables
    
    /// The ID of the Jamf policy used for the recon (inventory update)
    var reconPolicyID: String {
        switch DeviceManagementHelper.shared.state {
        case .managed(env: let env):
            return env.reconPolicyID ?? "null"
        default:
            return ""
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
        logger.log("jamfReconManager.runJamfRecon: Silently starting Self Service.", type: .default)
        _ = NSAppleScript(source: "do shell script \"/usr/bin/open -j '\(AppContext.storePath)'\"")?.executeAndReturnError(nil)
    }
    
    /// Asynchronously queues and starts the Jamf recon policy, then waits for it to begin running
    func queueReconPolicy() async {
        logger.log("jamfReconManager.runJamfRecon: Running Jamf Inventory Update policy in the queue.", type: .default)
        _ = NSAppleScript(source: "do shell script \"/usr/bin/open -g 'jamfselfservice://content?entity=policy&id=\(reconPolicyID)&action=execute'\"")?.executeAndReturnError(nil)
        await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                sleep(10)
                while await !self.isReconRunning {
                    sleep(2)
                }
                continuation.resume()
            }
        }
    }
    
    /// Immediately runs the Jamf recon policy without waiting for its execution
    func runReconPolicy() {
        logger.log("jamfReconManager.runJamfRecon: Running Jamf Inventory Update policy.", type: .default)
        _ = NSAppleScript(source: "do shell script \"/usr/bin/open -g 'jamfselfservice://content?entity=policy&id=\(reconPolicyID)&action=execute'\"")?.executeAndReturnError(nil)
    }
    
    /// Asynchronously waits for the completion of the Jamf recon process
    func waitForReconCompletion() async {
        logger.log("jamfReconManager.runJamfRecon: Tracking the completion of the Jamf Inventory Update.", type: .default)
        await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                sleep(10)
                while await self.isReconRunning {
                    sleep(2)
                }
                continuation.resume()
            }
        }
    }
    
    /// Kills the Self Service application if it is currently running
    func killSelfService() {
        logger.log("jamfReconManager.runJamfRecon: Closing Self Service.", type: .default)
        _ = NSAppleScript(source: "do shell script \"killall 'Self Service'\"")?.executeAndReturnError(nil)
    }
}
