//
//  JamfReconView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 22/08/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// Not used anymore
/// Struct representing the page that guide the user to run an inventory update.
struct JamfReconView: View {
    
    // MARK: - Private Constants
    
    /// Logger instance.
    private let logger: MLogger = MLogger.main
    
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
                .font(.system(size: 27, weight: .bold))
                .padding(.bottom, 8)
            Text(String(format: "recon.page.body.label".localized, AppContext.orgName, "recon.page.main.button.run.label".localized))
                .multilineTextAlignment(.center)
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
        })
        .onAppear {
            Utils.Window.makeWindowFloating()
        }
    }
    
    var mainButtonLabel: some View {
        Text("recon.page.main.button.run.label")
            .padding(4)
    }
    
    // MARK: - Private Methods
    
    private func didPressMainButton() async {
        await MainActor.run {
            runningRecon.toggle()
        }
        logger.log("jamfReconView.runJamfRecon: Starting Jamf Inventory Update", type: .default)
        var errors: NSDictionary?
        await withCheckedContinuation { continuation in
            Task.detached(priority: .background) {
                 _ = NSAppleScript(source: "do shell script \"/usr/local/bin/jamf recon\" with administrator privileges")?.executeAndReturnError(&errors)
                 continuation.resume()
             }
        }
        if errors == nil {
            logger.log("jamfReconView.runJamfRecon: Jamf Inventory Update completed", type: .default)
            await Utils.LaunchAgentHelpers.removeLaunchAgent()
            AppContext.isPostRebootPhase = false
            NSSound(named: .init("Funk"))?.play()
            action(.final)
        } else {
            logger.log("jamfReconView.runJamfRecon: Jamf Inventory Update completed with error: \(errors.debugDescription)", type: .default)
            await MainActor.run {
                encounteredError.toggle()
            }
        }
        await MainActor.run {
            runningRecon.toggle()
        }
    }
}

#Preview {
    JamfReconView(action: { _ in })
        .frame(width: 812, height: 600)
}
