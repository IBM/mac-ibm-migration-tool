//
//  Utils.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 14/11/2023.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import os.log
import Foundation
import AppKit

/// Utility functions for logging messages, retrieving interface styles, free space on the device,
/// and getting the user's folder name.
struct Utils {
    /// Retrieves the free space on the device.
    static var freeSpaceOnDevice: Int {
        let fileURL = FileManager.default.homeDirectoryForCurrentUser
        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage {
                let freeSpace = Int(capacity)
                return freeSpace
            } else {
                return 0
            }
        } catch {
            return 0
        }
    }
    
    /// Retrieves the user's folder name.
    static var userFolderName: String {
        return FileManager.default.homeDirectoryForCurrentUser.lastPathComponent
    }
    
    /// Retrieves the status of iCloud on the device.
    static var iCloudAvailable: Bool {
        return FileManager.default.ubiquityIdentityToken != nil
    }
    
    /// The correct page to use for runnin Jamf Inventory Update based on the desired method.
    static var reconPage: MigratorPage {
        switch AppContext.jamfReconMethod {
        case .direct:
            return .recon
        case .selfServicePolicy:
            return .final
        }
    }
    
    static var systemSettingsLabel: String {
        if #available(macOS 13.0, *) {
            return "common.system.settings.ventura.label".localized
        } else {
            return "common.system.settings.pre.ventura.label".localized
        }
    }
    
    /// Generate a random code.
    /// - Parameter digits: number of digits of the code.
    /// - Returns: string with the generated code.
    static func generateRandomCode(digits: Int) -> String {
        var number = String()
        for _ in 1...digits {
           number += "\(Int.random(in: 1...9))"
        }
        return number
    }
    
    /// Prevents the display from sleeping.
    static func preventSleep() {
        MLogger.main.log("utils.preventSleep: Preventing Mac to enter sleep.", type: .default)
        var assertionID: IOPMAssertionID = IOPMAssertionID(0)
        _ = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Prevent display sleep during critical operations" as CFString, &assertionID) == kIOReturnSuccess
        
    }
    
    /// Restart the device using an Apple Script to communicate with "System Events"
    static func rebootMac() {
        MLogger.main.log("utils.rebootMac: Restarting Mac.", type: .default)
        var errors: NSDictionary?
        _ = NSAppleScript(source: "tell app \"System Events\" to restart")?.executeAndReturnError(&errors)
    }
    
    /// Install a Launch Agent on the device to restart the app once the planned reboot happen.
    static func installLaunchAgent() async {
        MLogger.main.log("utils.installLaunchAgent: Creating Launch Agent plist.", type: .default)
        let fileContent = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>mac.ibm.shift</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/\(Bundle.main.name).app/Contents/MacOS/\(Bundle.main.name)</string>
    </array>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
"""
        FileManager.default.createFile(atPath: FileManager.default.homeDirectoryForCurrentUser.relativePath + "/Library/LaunchAgents/com.ibm.cio.be.migrator.plist", contents: fileContent.data(using: .utf8)!)
        MLogger.main.log("utils.installLaunchAgent: Loading Launch Agent.", type: .default)
        await withCheckedContinuation { continuation in
            _ = NSAppleScript(source: "do shell script \"launchctl bootstrap gui/501 \(FileManager.default.homeDirectoryForCurrentUser.relativePath + "/Library/LaunchAgents/com.ibm.cio.be.migrator.plist") \"")?.executeAndReturnError(nil)
            continuation.resume()
        }
        MLogger.main.log("utils.installLaunchAgent: Launch Agent installed.", type: .default)
    }
    
    /// Remove the Launch Agent from the device.
    static func removeLaunchAgent() async {
        MLogger.main.log("utils.removeLaunchAgent: Unloading Launch Agent.", type: .default)
        await withCheckedContinuation { continuation in
            _ = NSAppleScript(source: "do shell script \"launchctl bootout gui/501 \(FileManager.default.homeDirectoryForCurrentUser.relativePath + "/Library/LaunchAgents/com.ibm.cio.be.migrator.plist") \"")?.executeAndReturnError(nil)
            continuation.resume()
        }
        MLogger.main.log("utils.removeLaunchAgent: Removing Launch Agent plist.", type: .default)
        do {
            try FileManager.default.removeItem(atPath: FileManager.default.homeDirectoryForCurrentUser.relativePath + "/Library/LaunchAgents/com.ibm.cio.be.migrator.plist")
            MLogger.main.log("utils.removeLaunchAgent: Launch Agent removed.", type: .default)
        } catch {
            MLogger.main.log("utils.removeLaunchAgent: Error encountered while removing Launch Agent plist. Error: \(error.localizedDescription).", type: .default)
        }
    }
    
    /// Set the window level for the app to "floating" or "normal" based on the flag.
    /// - Parameter floating: if true the window level is set to "floating", if false the window leve is set to "normal"
    static func makeWindowFloating(_ floating: Bool = true) {
        MLogger.main.log("utils.makeWindowFloating: Setting app windows level to \(floating ? "floating" : "normal").", type: .default)
        for window in NSApplication.shared.windows {
            window.level = floating ? .floating : .normal
        }
    }
    
    /// Remove the `Close` UI button from the app Toolbar.
    static func removeClosableToolbarElement() {
        for window in NSApplication.shared.windows {
            window.styleMask.subtract(.closable)
        }
    }
    
    /// Restore the `Close` UI button in the app Toolbar.
    static func restoreClosableToolbarElement() {
        for window in NSApplication.shared.windows {
            window.styleMask.update(with: .closable)
        }
    }
    
    static func parseProfileURL(_ urlString: String) -> URL? {
        if urlString.contains("$HOMEFOLDER") {
            var finalUrl = urlString.replacingOccurrences(of: "$HOMEFOLDER", with: "")
            if finalUrl.starts(with: "/") {
                finalUrl.removeFirst()
            }
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(finalUrl)
        }
        if urlString.contains("$APPFOLDER") {
            var finalUrl = urlString.replacingOccurrences(of: "$APPFOLDER", with: "")
            if finalUrl.starts(with: "/") {
                finalUrl.removeFirst()
            }
            return FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent(finalUrl)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(urlString)
    }
}
