//
//  CodeVerificationView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 07/03/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI
import Combine

struct CodeVerificationView: View {
    // MARK: - Environment Variables

    @Environment(\.colorScheme) var colorScheme
    
    // MARK: - Constants
    
    /// Closure to execute when an action requires navigation to a different page.
    let action: (MigratorPage) -> Void
    /// The previous page to navigate back to, by default set to the welcome page.
    let previousPage: MigratorPage = .browser
    /// The next page to navigate forward to, typically the migration setup page.
    let nextPage: MigratorPage = .migrationSetup
    
    // MARK: - Observable Variables
    
    /// Observable object to control and observe migration browser-related activities.
    @ObservedObject var migrationController: MigrationController = MigrationController.shared
    
    // MARK: - Focus State Variables
    
    /// Focus state of the code verification field.
    @FocusState private var isTextFieldFocused: Bool
    
    // MARK: - State Variables
    
    @State private var verificationCode: String = ""
    /// State variable to indicate whether the browser is in a loading state.
    @State private var isLoading: Bool = false
    /// Tracks the visibility of the connection error alert.
    @State private var showConnectionError: Bool = false
    /// Tracks the visibility of the code error alert.
    @State private var showCodeError: Bool = false
    
    // MARK: - Views
    
    var body: some View {
        VStack {
            Image("icon")
                .resizable()
                .frame(width: 86, height: 86)
                .padding(.top, 55)
                .padding(.bottom, 8)
            Text("code.verification.page.title")
                .multilineTextAlignment(.center)
                .font(.system(size: 27, weight: .bold))
                .padding(.bottom, 8)
            Text("code.verification.page.subtitle")
                .multilineTextAlignment(.center)
                .padding(.bottom)
                .padding(.horizontal, 40)
            CodeVerificationFieldView(code: $verificationCode)
                .disabled(isLoading)
                .focused($isTextFieldFocused)
            Spacer()
            Divider()
            HStack {
                Spacer()
                Button(action: {
                    didPressSecondaryButton()
                }, label: {
                    secondaryButtonLabel
                })
                .disabled(isLoading)
                .keyboardShortcut(.cancelAction)
                ZStack {
                    Button(action: {
                        didPressMainButton()
                    }, label: {
                        mainButtonLabel
                    })
                    .disabled(verificationCode.count < 6)
                    .hiddenConditionally(isHidden: isLoading)
                    .keyboardShortcut(.defaultAction)
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .hiddenConditionally(isHidden: !isLoading)
                }
                .padding(.leading, 6)
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
        }
        .alert("code.verification.alert.code.error.title", isPresented: $showCodeError) {
            Button("code.verification.alert.code.error.action") {
                Task { @MainActor in
                    self.isLoading = false
                }
            }
        } message: {
            Text("code.verification.alert.code.error.message")
        }
        .alert("code.verification.alert.connection.error.title", isPresented: $showConnectionError) {
            Button("code.verification.alert.connection.error.action") {
                action(previousPage)
            }
        } message: {
            Text("code.verification.alert.connection.error.message")
        }
        .onReceive(migrationController.$migrationState, perform: { newState in
            switch newState {
            case .fetching:
                isLoading = true
            case .connectionEstablished:
                action(nextPage)
            case .wrongOTPCodeSent:
                showCodeError.toggle()
            default:
                break
            }
        })
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isTextFieldFocused = true
            }
        }
    }
    
    var mainButtonLabel: some View {
        Text("browser.page.button.main.label")
            .padding(4)
    }
    
    var secondaryButtonLabel: some View {
        Text("browser.page.button.secondary.label")
            .padding(4)
    }
    
    // MARK: - Private Methods
    
    private func didPressMainButton() {
        self.isLoading = true
        migrationController.connect(to: migrationController.selectedBrowserResult, withPasscode: verificationCode)
    }
    
    private func didPressSecondaryButton() {
        migrationController.selectedBrowserResult = nil
        action(previousPage)
    }
}

#Preview {
    CodeVerificationView(action: { _ in })
}
