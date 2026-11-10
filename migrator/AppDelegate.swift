//
//  AppDelegate.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 08/08/2024.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    
    // MARK: - Variables
    
    var isDeviceConnectedToPower: Bool = false {
        didSet {
            NotificationCenter.default.post(name: .devicePowerStatusChanged, object: nil, userInfo: ["newValue" : isDeviceConnectedToPower])
        }
    }

    // MARK: - Private Variables
    
    private var timer: Timer?
    
    /// True while the quit confirmation sheet is on screen.
    private var isQuitConfirmationPending = false

    // MARK: - Instance Functions
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Register fallback values for all managed keys so they are always present in
        // UserDefaults.standard.dictionaryRepresentation(). This must run before any
        // view body or managed AppContext property is evaluated, ensuring that
        // Utils.UserDefaultsHelpers.customizedKeys captures the complete key set.
        Utils.UserDefaultsHelpers.registerManagedDefaults()
        MLogger.main.log("appDelegate.applicationWillFinishLaunching: ===== launching \"\(Bundle.main.name)\" v\(Bundle.main.marketingVersion) (\(Bundle.main.buildNumber)) on \(ProcessInfo.processInfo.operatingSystemVersionString), host \"\(Host.current().localizedName ?? "unknown")\", log level: \(AppContext.loggingLevel.rawValue) =====", type: .default)
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
        if AppContext.isPostRebootPhase {
            showWindowIfMissingAfterRebootLaunch()
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Returns true to quit the app when the last window is closed.
        return true
    }
    
    /// Single entry point for every quit path (cmd-Q, menu item, Dock menu, window close button):
    /// asks the user for confirmation before the app terminates.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Never block a logout, restart or shutdown initiated by the system.
        let quitReason = NSAppleEventManager.shared().currentAppleEvent?.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue ?? 0
        guard quitReason == 0 else { return .terminateNow }
        // A confirmation is already on screen, ignore repeated requests.
        guard !isQuitConfirmationPending else { return .terminateCancel }
        isQuitConfirmationPending = true
        
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "common.app.attention".localized
        alert.informativeText = String(format: "common.app.quit.alert.message".localized, Bundle.main.name)
        let quitButton = alert.addButton(withTitle: "common.app.quit.alert.button.quit".localized)
        quitButton.hasDestructiveAction = true
        alert.addButton(withTitle: "common.app.quit.alert.button.cancel".localized)
        
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else {
            let confirmed = alert.runModal() == .alertFirstButtonReturn
            isQuitConfirmationPending = false
            return confirmed ? .terminateNow : .terminateCancel
        }
        alert.beginSheetModal(for: window) { [weak self] response in
            self?.isQuitConfirmationPending = false
            NSApplication.shared.reply(toApplicationShouldTerminate: response == .alertFirstButtonReturn)
        }
        return .terminateLater
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        Utils.UserDefaultsHelpers.cleanUpCustomKeys()
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
    
    /// An app relaunched after the planned reboot can come up with no window until the user
    /// clicks its Dock icon, so the post-reboot workflow never starts. If nothing is visible
    /// shortly after launch, activate the app and re-open it, which is the same event a Dock
    /// click sends and makes SwiftUI create the window.
    private func showWindowIfMissingAfterRebootLaunch() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            let hasVisibleWindow = NSApplication.shared.windows.contains { $0.isVisible && $0.canBecomeMain }
            MLogger.main.log("appDelegate.showWindowIfMissingAfterRebootLaunch: visible window present: \(hasVisibleWindow)", type: .default)
            NSApplication.shared.activate(ignoringOtherApps: true)
            guard !hasVisibleWindow else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
        }
    }
    
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
        // Routes the close button through applicationShouldTerminate, which asks for confirmation.
        NSApplication.shared.terminate(nil)
        return false
    }
}
