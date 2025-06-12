//
//  RebootView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 22/08/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// Struct representing the page that ask the user to restart the device.
struct RebootView: View {
    
    // MARK: - Constants

    /// Closure to execute when an action requires navigation to a different page.
    let action: (MigratorPage) -> Void
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - State Variables
    
    /// State variable that tracks the time left to force the device reboot.
    @State private var timeLeft: Int = 120

    // MARK: - Views
    
    var body: some View {
        VStack {
            Image("icon")
                .resizable()
                .frame(width: 86, height: 86)
                .padding(.top, 55)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            Text("reboot.page.title.label")
                .multilineTextAlignment(.center)
                .font(.system(size: 27, weight: .bold))
                .padding(.bottom, 8)
            Text("reboot.page.body.label")
                .multilineTextAlignment(.center)
                .padding(.bottom)
                .padding(.horizontal, 40)
            Spacer()
            Divider()
            HStack {
                Text(String(format: "reboot.page.bottom.timer.label".localized, timeLeft.timeFormattedString))
                    .font(.title3)
                    .bold()
                Spacer()
                Button(action: {
                    didPressMainButton()
                }, label: {
                    mainButtonLabel
                })
                .buttonStyle(.bordered)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("accessibility.rebootPage.reboot.button.hint")
                .padding(.leading, 6)
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
        }
        .onReceive(timer) { _ in
            guard timeLeft >= 1 else {
                self.timer.upstream.connect().cancel()
                didPressMainButton()
                return
            }
            timeLeft -= 1
        }
        .onAppear {
            Utils.makeWindowFloating()
        }
    }
    
    var mainButtonLabel: some View {
        Text("reboot.page.main.button.label")
            .padding(4)
    }
    
    // MARK: - Private Methods
    
    private func didPressMainButton() {
        AppContext.isPostRebootPhase = true
        Task {
            await Utils.installLaunchAgent()
            Utils.rebootMac()
        }
    }
}

#Preview {
    RebootView(action: { _ in })
        .frame(width: 812, height: 600)
}
