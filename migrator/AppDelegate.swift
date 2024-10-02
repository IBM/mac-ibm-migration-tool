//
//  AppDelegate.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 08/08/2024.
//  © Copyright IBM Corp. 2023, 2024
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
        Utils.preventSleep()
#endif
        Task { @MainActor in
            if let mainMenu = NSApplication.shared.mainMenu,
               let appMenu = mainMenu.items.first(where: { $0.title == Bundle.main.name }),
               let aboutItem = appMenu.submenu?.items.first?.copy() as? NSMenuItem {
//               let helpMenu = mainMenu.items.last {
                let firstMenu = NSMenuItem(title: Bundle.main.name, action: nil, keyEquivalent: "")
                firstMenu.submenu = NSMenu(title: Bundle.main.name)
                firstMenu.submenu?.addItem(aboutItem)
                mainMenu.items.removeAll()
                mainMenu.items.append(firstMenu)
                // menu.items.append(helpMenu)
            }
        }
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
        // Cleaning temporary settings sent by the source device.
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        UserDefaults.standard.synchronize()
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
