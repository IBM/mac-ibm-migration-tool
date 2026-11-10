//
//  JamfReconView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 22/08/2024.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// Not used anymore
/// Struct representing the page that guide the user to run an inventory update.
struct JamfReconView: View {
    
    // MARK: - Private Constants
    
    /// Logger instance.
    private let logger = MLogger.main.scoped(to: .device)
    
    // MARK: - Constants

    /// Closure to execute when an action requires navigation to a different page.
    let action: (MigratorPage) -> Void
    
    // MARK: - State Variables
    
    /// Boolean variable to track if the recon operation is running.
    @State private var runningRecon: Bool = false
    /// Boolean variable to track whenever the recon operation encounter an error.
    @State private var encounteredError: Bool = false
    
    // MARK: - Views
    
    var body: some View {
        VStack {
            CustomizableIconView(pageIdentifier: "jamfRecon")
                .padding(.top, 55)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            Text("recon.page.title.label")
                .multilineTextAlignment(.center)
                .customFont(.largeTitle, weight: .bold)
                .padding(.bottom, 8)
            Text(String(format: "recon.page.body.label".localized, AppContext.orgName, "recon.page.main.button.run.label".localized))
                .multilineTextAlignment(.center)
                .customFont(.body)
                .padding(.bottom)
                .padding(.horizontal, 40)
            Spacer()
            Divider()
            HStack {
                if runningRecon {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                    Text("recon.page.informational.bottom.ongoing.label")
                        .customFont(.body)
                        .padding(.leading, 8)
                }
                Spacer()
                Button(action: {
                    Task {
                        await didPressMainButton()
                    }
                }, label: {
                    mainButtonLabel
                })
                .buttonStyle(.bordered)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("accessibility.jamfReconPage.runRecon.button.hint")
                .disabled(runningRecon)
                .padding(.leading, 6)
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
        }
        .alert("recon.page.alert.error.title", isPresented: $encounteredError, actions: { }, message: {
            Text("recon.page.alert.error.message")
                .customFont(.body)
        })
        .onAppear {
            Utils.Window.makeWindowFloating()
        }
    }
    
    var mainButtonLabel: some View {
        Text("recon.page.main.button.run.label")
            .customFont(.body)
            .padding(4)
    }
    
    // MARK: - Private Methods
    
    private func didPressMainButton() async {
        runningRecon.toggle()
        logger.log("jamfReconView.runJamfRecon: Starting Jamf Inventory Update", type: .default)
        // `NSDictionary` isn't `Sendable`, so the error is described to a plain `String` before
        // crossing back from the detached task.
        let errorDescription: String? = await Task.detached(priority: .background) {
            var errors: NSDictionary?
            _ = NSAppleScript(source: "do shell script \"/usr/local/bin/jamf recon\" with administrator privileges")?.executeAndReturnError(&errors)
            return errors?.debugDescription
        }.value
        if let errorDescription {
            logger.log("jamfReconView.runJamfRecon: Jamf Inventory Update completed with error: \(errorDescription)", type: .default)
            encounteredError.toggle()
        } else {
            logger.log("jamfReconView.runJamfRecon: Jamf Inventory Update completed", type: .default)
            await Utils.LaunchAgentHelpers.removeLaunchAgent()
            AppContext.isPostRebootPhase = false
            NSSound(named: .init("Funk"))?.play()
            action(.final)
        }
        runningRecon.toggle()
    }
}

#Preview {
    JamfReconView(action: { _ in })
        .frame(width: 812, height: 600)
}
