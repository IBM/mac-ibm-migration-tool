//
//  MigratorApp.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 14/11/2023.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import AppKit
import SwiftUI
import IOKit.pwr_mgt

@main
struct MigratorApp: App {
    
    // Integrates a traditional AppDelegate to use functionalities not supported by SwiftUI.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    
    // MARK: - State Variables
    
    @State private var currentWindow: NSWindow?
    @State private var showQuitConfirmationAlert: Bool = false
    
    // MARK: - Views
    
    // Defines the main content and behavior of the app's window.
    var body: some Scene {
        WindowGroup {
            MainView()
                .background(WindowAccessor(window: self.$currentWindow))
                .onReceive(self.appDelegate.$userRequestToQuit, perform: { newValue in
                    self.showQuitConfirmationAlert = newValue
                })
                .alert(isPresented: self.$showQuitConfirmationAlert, content: {
                    Alert(title: Text("common.app.attention"),
                          message: Text(String(format: "common.app.quit.alert.message".localized, Bundle.main.name)),
                          primaryButton: .cancel(),
                          secondaryButton: .destructive(Text("common.app.quit.alert.button.quit"), action: { appDelegate.quit() }))
                })
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appVisibility) { }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizabilityContentSize()
    }
}
