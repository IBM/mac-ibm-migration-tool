//
//  AppleIDView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 15/08/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// Struct representing the page to visualize the Apple ID status and remediation steps.
struct AppleIDView: View {
    
    // MARK: - Private Constants
    
    /// Logger instance.
    private let logger: MLogger = MLogger.main
    
    // MARK: - Constants

    /// Closure to execute when an action requires navigation to a different page.
    let action: (MigratorPage) -> Void
    
    // MARK: - Views
    
    var body: some View {
        VStack {
            Image("apple_id_icon")
                .resizable()
                .frame(width: 86, height: 86)
                .padding(.top, 55)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            Text("icloud.page.title.label")
                .multilineTextAlignment(.center)
                .font(.system(size: 27, weight: .bold))
                .padding(.bottom, 8)
            Text(String(format: "icloud.page.body.label".localized, Utils.Common.systemSettingsLabel, "icloud.page.main.button.label".localized))
                .multilineTextAlignment(.center)
                .padding(.bottom)
                .padding(.horizontal, 40)
            Spacer()
            Button(action: {
                logger.log("appleIDView.mainButtonAction: Opening Apple ID Preferences Panel", type: .default)
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane")!)
            }, label: {
                Text(String(format: "icloud.page.system.settings.button.label".localized, Utils.Common.systemSettingsLabel))
                    .padding(4)
            })
            .keyboardShortcut(.defaultAction)
            .accessibilityHint("accessibility.appleIDPage.systemPreferences.button.hint")
            .padding(.bottom, 6)
            Divider()
            HStack {
                ProgressView()
                    .controlSize(.small)
                Spacer()
                Button(action: {
                    goToNextPage()
                }, label: {
                    mainButtonLabel
                })
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .accessibilityHint("accessibility.appleIDPage.skip.button.hint")
                .padding(.leading, 6)
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.NSUbiquityIdentityDidChange)) { _ in
            if FileManager.default.ubiquityIdentityToken != nil { goToNextPage() }
        }
        .onAppear {
            Utils.Window.makeWindowFloating(false)
        }
    }
    
    var mainButtonLabel: some View {
        Text("icloud.page.main.button.label")
            .padding(4)
    }
    
    // MARK: - Private Methods
    
    private func goToNextPage() {
        action(.appleID.next())
    }
}

#Preview {
    AppleIDView(action: { _ in })
        .frame(width: 812, height: 600)
}
