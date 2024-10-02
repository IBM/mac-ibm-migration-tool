//
//  FinalView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 22/08/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// Struct representing the final page that show the user the result of the migration process.
struct FinalView: View {
    
    // MARK: - Enum
    
    enum ReconState {
        case notRunning
        case queued
        case running
        case done
    }
    
    // MARK: - Private Constants
    
    /// Logger instance.
    private let logger: MLogger = MLogger.main
    
    private let jamfReconManager: JamfReconManager = JamfReconManager()
    
    // MARK: - Environment Variables
    
    @EnvironmentObject private var appDelegate: AppDelegate
    
    // MARK: - State Variables
    
    /// Boolean variable to track if the recon operation is running.
    @State private var reconState: ReconState = .notRunning
        
    // MARK: - Views
    
    var body: some View {
        VStack {
            Image("icon")
                .resizable()
                .frame(width: 86, height: 86)
                .padding(.top, 55)
                .padding(.bottom, 8)
            if reconState != .done && DeviceManagementHelper.shared.isJamfReconAvailable {
                Text("final.page.title.recon.label")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 27, weight: .bold))
                    .padding(.bottom, 8)
                Text(String(format: "final.page.body.recon.label".localized, AppContext.orgName))
                    .multilineTextAlignment(.center)
                    .padding(.bottom)
                    .padding(.horizontal, 40)
            } else {
                Text("final.page.title.label")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 27, weight: .bold))
                    .padding(.bottom, 8)
                Text("final.page.body.label")
                    .multilineTextAlignment(.center)
                    .padding(.bottom)
                    .padding(.horizontal, 40)
            }
            VStack(alignment: .center) {
                HStack {
                    Image(systemName: "shippingbox.and.arrow.backward.fill")
                        .resizable()
                        .frame(width: 52, height: 34.125)
                    Text("final.page.body.component.migration.title.label")
                        .font(.title2)
                        .padding(.leading, 8)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .frame(width: 25, height: 25)
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 8)
                if !AppContext.shouldSkipAppleIDCheck {
                    Divider()
                    HStack {
                        Image(systemName: "apple.logo")
                            .resizable()
                            .frame(width: 27.3, height: 34.125)
                            .padding(.horizontal, 11.35)
                        Text("final.page.body.component.appleid.title.label")
                            .font(.title2)
                            .padding(.leading, 8)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .frame(width: 25, height: 25)
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                }
                if !AppContext.shouldSkipDeviceReboot {
                    Divider()
                    HStack {
                        Image(systemName: "macbook.gen2")
                            .resizable()
                            .frame(width: 52, height: 34.125)
                        Text("final.page.body.component.reboot.title.label")
                            .font(.title2)
                            .padding(.leading, 8)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .frame(width: 25, height: 25)
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                }
                if DeviceManagementHelper.shared.isJamfReconAvailable {
                    Divider()
                    HStack {
                        Image(systemName: "arrow.clockwise.icloud.fill")
                            .resizable()
                            .frame(width: 52, height: 34.125)
                        Text("final.page.body.component.inventory.title.label")
                            .font(.title2)
                            .padding(.leading, 8)
                        Spacer()
                        switch reconState {
                        case .notRunning:
                            EmptyView()
                        case .queued:
                            Text("final.page.recon.state.queued.label")
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 25, height: 25)
                        case .running:
                            Text("final.page.recon.state.running.label")
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 25, height: 25)
                        case .done:
                            Image(systemName: "checkmark.circle.fill")
                                .resizable()
                                .frame(width: 25, height: 25)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                    .task(priority: .background) {
                        await runJamfRecon()
                    }
                } else {
                    Divider()
                        .hidden()
                }
            }
            .background {
                Color("discoveryViewBackground")
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: Color(red: 0, green: 0, blue: 0, opacity: 0.15), radius: 6, x: 0, y: 0)
            }
            .padding(.horizontal, 200)
            .padding(.bottom, 16)
            Spacer()
            Divider()
            HStack {
                Image(systemName: "exclamationmark.circle")
                    .resizable()
                    .frame(width: 20, height: 20)
                Text("final.page.bottom.informational.label")
                Spacer()
                Button(action: {
                    appDelegate.quit()
                }, label: {
                    mainButtonLabel
                })
                .buttonStyle(.bordered)
                .keyboardShortcut(.defaultAction)
                .padding(.leading, 6)
                .disabled(reconState != .done && DeviceManagementHelper.shared.isJamfReconAvailable)
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
        }
    }
    
    var mainButtonLabel: some View {
        Text("final.page.main.button.label")
            .padding(4)
    }
    
    // MARK: - Private Methods
    
    /// Run inventory update against Jamf instance using a shell script.
    private func runJamfRecon() async {
        guard AppContext.jamfReconMethod != .direct else {
            reconState = .done
            await Utils.removeLaunchAgent()
            AppContext.isPostRebootPhase = false
            NSSound(named: .init("Funk"))?.play()
            return
        }
        logger.log("finalView.runJamfRecon: Starting Jamf Inventory Update Workflow.", type: .default)
        if await jamfReconManager.isSelfServiceRunning {
            logger.log("finalView.runJamfRecon: Self Service already running.", type: .default)
            if await jamfReconManager.isReconRunning {
                logger.log("finalView.runJamfRecon: Jamf Inventory Update already running.", type: .default)
                reconState = .running
                await jamfReconManager.waitForReconCompletion()
            } else {
                if await jamfReconManager.areJamfPoliciesRunning {
                    reconState = .queued
                    await jamfReconManager.queueReconPolicy()
                    reconState = .running
                } else {
                    reconState = .running
                    await jamfReconManager.runReconPolicy()
                }
                await jamfReconManager.waitForReconCompletion()
            }
        } else {
            reconState = .running
            await jamfReconManager.silentlyRunSelfService()
            sleep(5)
            await jamfReconManager.runReconPolicy()
            await jamfReconManager.waitForReconCompletion()
            await jamfReconManager.killSelfService()
        }
        reconState = .done
        logger.log("finalView.runJamfRecon: Jamf Inventory Update completed", type: .default)
        await Utils.removeLaunchAgent()
        AppContext.isPostRebootPhase = false
        NSSound(named: .init("Funk"))?.play()
    }
}

#Preview {
    FinalView()
        .frame(width: 812, height: 600)
}
