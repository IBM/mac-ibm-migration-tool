//
//  CodeVerificationView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 07/03/2024.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI
import Combine

/// View for verifying the connection code between devices during migration.
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
    /// Tracks the visibility of the "the other device declined" alert.
    @State private var showDeclinedError: Bool = false
    /// Guards against starting a second connection attempt if this view re-appears.
    @State private var hasStartedConnecting: Bool = false
    
    // MARK: - Views
    
    var body: some View {
        VStack {
            CustomizableIconView(pageIdentifier: "codeVerification")
                .padding(.top, 55)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            Text("code.verification.page.title")
                .multilineTextAlignment(.center)
                .customFont(.largeTitle, weight: .bold)
                .padding(.bottom, 8)
                .accessibilitySortPriority(1)
            Text("code.verification.page.subtitle")
                .multilineTextAlignment(.center)
                .customFont(.body)
                .padding(.bottom)
                .padding(.horizontal, 40)
                .accessibilitySortPriority(0.9)
            if migrationController.isAwaitingPasscodeEntry {
                CodeVerificationFieldView(code: $verificationCode)
                    .disabled(isLoading)
                    .focused($isTextFieldFocused)
                    .accessibilitySortPriority(0.8)
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .accessibilityHidden(true)
                    Text("code.verification.page.waiting.label")
                        .customFont(.body)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer()
            Divider()
            HStack {
                Spacer()
                Button(action: {
                    didPressSecondaryButton()
                }, label: {
                    secondaryButtonLabel
                })
                .keyboardShortcut(.cancelAction)
                .accessibilityHint("accessibility.cvPage.mainButton.hint")
                if migrationController.isAwaitingPasscodeEntry {
                    ZStack {
                        Button(action: {
                            didPressMainButton()
                        }, label: {
                            mainButtonLabel
                        })
                        .disabled(verificationCode.count < 6)
                        .hiddenConditionally(isHidden: isLoading)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityHint("accessibility.cvPage.secondaryButton.hint")
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                            .hiddenConditionally(isHidden: !isLoading)
                    }
                    .padding(.leading, 6)
                }
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
        }
        .alert("code.verification.alert.code.error.title", isPresented: $showCodeError) {
            Button("code.verification.alert.code.error.action") {
                Task { @MainActor in
                    self.isLoading = false
                    self.verificationCode = ""
                    // A wrong code always ends with the underlying connection torn down (the
                    // PAKE can't just be retried over the same session), so retrying needs a
                    // genuinely fresh connection - which also means the destination will see a
                    // new accept/decline prompt rather than silently reusing the old approval.
                    migrationController.connect(to: migrationController.selectedBrowserResult)
                }
            }
            .accessibilityHint("accessibility.cvPage.error.button.hint")
        } message: {
            Text("code.verification.alert.code.error.message")
                .customFont(.body)
        }
        .alert("code.verification.alert.connection.error.title", isPresented: $showConnectionError) {
            Button("code.verification.alert.connection.error.action") {
                action(previousPage)
            }
            .accessibilityHint("accessibility.cvPage.error.button.hint")
        } message: {
            Text("code.verification.alert.connection.error.message")
                .customFont(.body)
        }
        .alert("code.verification.alert.declined.title", isPresented: $showDeclinedError) {
            Button("code.verification.alert.declined.action") {
                action(previousPage)
            }
            .accessibilityHint("accessibility.cvPage.error.button.hint")
        } message: {
            Text("code.verification.alert.declined.message")
                .customFont(.body)
        }
        .onReceive(migrationController.$migrationState, perform: { newState in
            switch newState {
            case .connectionEstablished:
                action(nextPage)
            case .wrongOTPCodeSent:
                showCodeError.toggle()
            default:
                break
            }
        })
        .onChange(of: migrationController.pairingRequestWasDeclined) { _, wasDeclined in
            guard wasDeclined else { return }
            migrationController.pairingRequestWasDeclined = false
            isLoading = false
            showDeclinedError = true
        }
        .onChange(of: migrationController.isAwaitingPasscodeEntry) { _, isAwaiting in
            guard isAwaiting else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isTextFieldFocused = true
            }
        }
        .onAppear {
            guard !hasStartedConnecting else { return }
            hasStartedConnecting = true
            migrationController.connect(to: migrationController.selectedBrowserResult)
        }
    }
    
    var mainButtonLabel: some View {
        Text("browser.page.button.main.label")
            .customFont(.body)
            .padding(4)
    }
    
    var secondaryButtonLabel: some View {
        Text("code.verification.page.button.secondary.label")
            .customFont(.body)
            .padding(4)
    }
    
    // MARK: - Private Methods
    
    private func didPressMainButton() {
        self.isLoading = true
        Task {
            await migrationController.submitPasscode(verificationCode)
        }
    }
    
    private func didPressSecondaryButton() {
        migrationController.cancelPairingRequest()
        migrationController.selectedBrowserResult = nil
        action(previousPage)
    }
}

#Preview {
    CodeVerificationView(action: { _ in })
}
