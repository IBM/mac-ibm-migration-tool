//
//  MigratorApp.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 14/11/2023.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import AppKit
import SwiftUI
import IOKit.pwr_mgt

@main
struct MigratorApp: App {
    
    enum MigratorAppSheets {
        case termsAndConditions
        case privacyPolicy
        case thirdPartyNotices
    }
    
    // Integrates a traditional AppDelegate to use functionalities not supported by SwiftUI.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    
    // MARK: - State Variables
    
    @State private var currentWindow: NSWindow?
    @State private var showQuitConfirmationAlert: Bool = false
    @State private var showTermsAndConditions: Bool = false
    @State private var showPrivacyPolicy: Bool = false
    @State private var showThirdPartyNotices: Bool = false
    
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
                .accessibilityElement(children: .contain)
                .accessibilityLabel("accessibility.mainWindow.label")
                .sheet(isPresented: $showTermsAndConditions) {
                    ResourceView(title: "common.app.menu.label.termsandconditon".localized, resource: AppContext.termsConditionsURL!)
                        .frame(width: 700, height: 600)
                }
                .sheet(isPresented: $showPrivacyPolicy) {
                    ResourceView(title: "common.app.menu.label.privacypolicy".localized, resource: AppContext.privacyPolicyURL!)
                        .frame(width: 700, height: 600)
                }
                .sheet(isPresented: $showThirdPartyNotices) {
                    ResourceView(title: "common.app.menu.label.tpnotices".localized, resource: AppContext.thirdPartyNoticesURL!)
                        .frame(width: 700, height: 600)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appVisibility) { }
            CommandGroup(replacing: .systemServices) { }
            CommandGroup(replacing: .appTermination) {
                if AppContext.termsConditionsURL != nil {
                    Button("common.app.menu.label.termsandconditon") {
                        self.toggleSheet(.termsAndConditions)
                    }
                }
                if AppContext.privacyPolicyURL != nil {
                    Button("common.app.menu.label.privacypolicy") {
                        self.toggleSheet(.privacyPolicy)
                    }
                }
                if AppContext.thirdPartyNoticesURL != nil {
                    Button("common.app.menu.label.tpnotices") {
                        self.toggleSheet(.thirdPartyNotices)
                    }
                }
                Divider()
                Button(String(format: "common.app.quit.menu.button".localized, Bundle.main.name)) {
                    self.showQuitConfirmationAlert = true
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizabilityContentSize()
    }
    
    private func toggleSheet(_ type: MigratorAppSheets) {
        if self.showTermsAndConditions { self.showTermsAndConditions = false }
        if self.showPrivacyPolicy { self.showPrivacyPolicy = false }
        if self.showThirdPartyNotices { self.showThirdPartyNotices = false }
        switch type {
        case .privacyPolicy:
            self.showPrivacyPolicy.toggle()
        case .termsAndConditions:
            self.showTermsAndConditions.toggle()
        case .thirdPartyNotices:
            self.showThirdPartyNotices.toggle()
        }
    }
}
