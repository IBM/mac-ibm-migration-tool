//
//  AppDelegate.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 08/08/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    
    // MARK: - Published variables
    
    /// Used to track user requests to quit the app.
    @Published var userRequestToQuit: Bool = false
    
    // MARK: - Variables
    
    var isDeviceConnectedToPower: Bool = false {
        didSet {
            NotificationCenter.default.post(name: .devicePowerStatusChanged, object: nil, userInfo: ["newValue" : isDeviceConnectedToPower])
        }
    }

    // MARK: - Private Variables
    
    private var timer: Timer?

    // MARK: - Instance Functions
    
    func applicationWillFinishLaunching(_ notification: Notification) {
#if !DEBUG
        // Prevent the execution of multiple instances of the app.
        guard NSWorkspace.shared.runningApplications.filter({ $0.bundleIdentifier == Bundle.main.bundleIdentifier }).count < 2 else { exit(0) }
#endif
        // Disables the automatic tabbing feature in macOS, providing more control over window management.
        NSWindow.allowsAutomaticWindowTabbing = false
        isDeviceConnectedToPower = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() != nil
        timer = Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(checkPowerStatus), userInfo: nil, repeats: true)
#if DEBUG
        Utils.Common.preventSleep()
#endif
        Task { @MainActor in
            if let mainMenu = NSApplication.shared.mainMenu,
               mainMenu.numberOfItems > 2 {
                mainMenu.removeItem(at: 1)
            }
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Tracks the cmd-q keyboard shortcut to avoid unhandled app quits.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.modifierFlags.intersection(.deviceIndependentFlagsMask) {
            case [.command] where event.characters == "q":
                self.userRequestToQuit = true
            default:
                return event
            }
            return event
        }
        MLogger.main.log("appDelegate:applicationDidFinishLaunching application did finish launching", type: .default)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Returns true to quit the app when the last window is closed.
        return true
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return false
    }
    
    // MARK: - Functions
    
    /// Runs final operations and quit the app
    func quit() {
        Utils.UserDefaultsHelpers.cleanUpCustomKeys()
        exit(0)
    }
    
    // MARK: - Private Functions
    
    /// Periodically check if the device is connected to the power adaptor.
    @objc
    private func checkPowerStatus() {
        let newValue = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() != nil
        if newValue != isDeviceConnectedToPower {
            isDeviceConnectedToPower = newValue
        }
    }
}

// MARK: - NSWindowDelegate methods implementation

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        Task { @MainActor in
            self.userRequestToQuit = true
        }
        return false
    }
}
