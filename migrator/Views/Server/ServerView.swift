//
//  DiscoveryView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 14/11/2023.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI
import Network

/// Struct representing the page to visualize the Server behaviour.
struct ServerView: View {
    
    // MARK: - Environment Variables

    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject private var appDelegate: AppDelegate

    // MARK: - Constants
    
    /// Closure to execute when an action requires navigation
    let action: (MigratorPage) -> Void
    /// The previous page to return to, defaulted to the welcome page
    let previousPage: MigratorPage = .welcome
    
    // MARK: - Observable Variables
    
    /// Observable object to control and observe migration status
    @ObservedObject var migrationController: MigrationController = MigrationController.shared
    /// Observable view model object to handle data and logic for the server view
    @ObservedObject var viewModel: ServerViewModel = ServerViewModel()
    
    // MARK: - State Variables
    
    /// State variable to track power warning popover appearance.
    @State private var showPowerPopover: Bool = false
    /// State variable to track local network warning popover appearance.
    @State private var showLocalNetworkPopover: Bool = true
    
    // MARK: - Initializers
    
    /// Custom initializer to set up the view with a navigation action and start the listening process.
    /// - Parameter action: the navigation action.
    init(action: @escaping (MigratorPage) -> Void) {
        self.action = action
    }

    // MARK: - Computed Properties

    /// Title for the pairing overlay, varying with `viewModel.pendingPairingAlert`.
    private var pairingAlertTitle: String {
        switch viewModel.pendingPairingAlert {
        case .none:
            return ""
        case .requestPending:
            return "server.page.pairing.request.title".localized
        case .accepted:
            return "server.page.pairing.code.alert.title".localized
        }
    }

    // MARK: - Views
    
    var body: some View {
        VStack {
            CustomizableIconView(pageIdentifier: "server")
                .padding(.top, 55)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            Text(viewModel.connectionEstablished ? (viewModel.migrationProgress > 0 ? (viewModel.migrationProgress == 1 ? "server.page.title.migration.complete.label" : "server.page.title.migration.ongoing.label") : "server.page.connected.title") : "server.page.title")
                .multilineTextAlignment(.center)
                .customFont(.largeTitle, weight: .bold)
                .padding(.bottom, 8)
            Text(viewModel.connectionEstablished ? (viewModel.migrationProgress > 0 ? (viewModel.migrationProgress == 1 ? "server.page.body.migration.complete.label" : "server.page.body.ongoing.label") :  "server.page.connected.subtitle") : "server.page.subtitle")
                .multilineTextAlignment(.center)
                .customFont(.body)
                .padding(.horizontal, 40)
                .padding(.bottom, viewModel.connectionEstablished ? 8 : 0)
            Image(viewModel.connectionEstablished ? "old_mac" : "new_mac")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 90, height: 90)
                .tint(Color("uiIcon"))
                .accessibilityHidden(true)
            if viewModel.connectionEstablished {
                HStack(spacing: 0) {
                    Text(viewModel.migrationProgress == 1 ? "migration.page.progressbar.top.complete.label".localized : "migration.page.progressbar.top.ongoing.label".localized)
                        .customFont(.body)
                    Text(migrationController.hostName).customFont(.body, weight: .bold)
                    Text(viewModel.usedInterface)
                        .customFont(.body)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            } else {
                Text(Host.current().localizedName ?? "server.page.default.device.name")
                    .customFont(.headline)
                    .padding(.bottom, 4)
                    .accessibilityHidden(true)
            }
            VStack {
                if viewModel.connectionEstablished {
                    if viewModel.migrationProgress == 0 {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .controlSize(.regular)
                            .accessibilityHidden(true)
                    } else {
                        ProgressView(value: viewModel.migrationProgress)
                            .progressViewStyle(.linear)
                            .controlSize(.regular)
                    }
                    HStack {
                        Spacer()
                        Text("\(viewModel.percentageCompleted)")
                            .customFont(.callout)
                    }
                } else {
                    VStack(spacing: 0) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                            .accessibilityHidden(true)
                        Spacer()
                        Text("server.page.pairing.waiting.label")
                            .customFont(.title3)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 176)
            Spacer()
            Divider()
            HStack(spacing: 4) {
                if !viewModel.deviceIsConnectedToPower {
                    Button {
                        showPowerPopover.toggle()
                    } label: {
                        Image(systemName: "exclamationmark")
                            .font(.title2)
                            .padding(4)
                    }
                    .clipShape(Circle())
                    .accessibilityLabel("accessibility.serverView.powerWarningButton.label")
                    .accessibilityHint("accessibility.serverView.powerWarningButton.hint")
                    .popover(isPresented: $showPowerPopover, arrowEdge: .bottom) {
                        Text("migration.page.warning.button.popover.text")
                            .customFont(.body)
                            .padding()
                    }
                }
                if viewModel.showLocalNetworkWarning && !viewModel.connectionEstablished {
                    Button {
                        showLocalNetworkPopover.toggle()
                    } label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.title2)
                            .padding(4)
                    }
                    .clipShape(Circle())
                    .accessibilityLabel("accessibility.serverView.localNetworkWarningButton.label")
                    .accessibilityHint("accessibility.serverView.localNetworkWarningButton.hint")
                    .popover(isPresented: $showLocalNetworkPopover, arrowEdge: .bottom) {
                        VStack(spacing: 8) {
                            Text(String(format: "server.page.localnetwork.warning.label".localized, Bundle.main.name, Utils.Common.systemSettingsLabel, Bundle.main.name))
                                .lineLimit(nil)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .customFont(.body)
                            Button {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocalNetwork") {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Text(String(format: "icloud.page.system.settings.button.label".localized, Utils.Common.systemSettingsLabel))
                                    .customFont(.body)
                            }
                        }
                        .frame(maxWidth: 300)
                        .padding()
                    }
                }
                Spacer()
                if viewModel.connectionEstablished {
                    Button(action: {
                        action(.server.next())
                    }, label: {
                        Text("server.page.button.main.continue.label")
                            .customFont(.body)
                            .padding(4)
                    })
                    .disabled(viewModel.migrationProgress != 1)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint("accessibility.serverView.connected.mainButton.hint")
                } else {
                    Button(action: {
                        migrationController.stopServer()
                        action(previousPage)
                    }, label: {
                        Text("server.page.button.main.label")
                            .customFont(.body)
                            .foregroundColor(.red)
                            .padding(4)
                    })
                    .keyboardShortcut(.cancelAction)
                    .accessibilityHint("accessibility.serverView.notConnected.mainButton.hint")
                }
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
            .frame(height: 56)
        }
        .overlay {
            if viewModel.isPaused {
                CustomAlertView(title: "server.page.paused.alert.title".localized,
                                message: String(format: "server.page.paused.alert.message".localized, viewModel.sourceHostName)) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.regular)
                }
            } else if viewModel.connectionInterrupted {
                CustomAlertView(title: "connection.error.alert.title".localized, message: "connection.error.alert.restoring.message".localized) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.regular)
                }
            } else if viewModel.isPairingLocked {
                CustomAlertView(title: "server.page.pairing.locked.alert.title".localized, message: "server.page.pairing.locked.alert.message".localized) {
                    Button {
                        viewModel.generateNewCodeAndUnlock()
                    } label: {
                        Text("server.page.pairing.locked.alert.button.label")
                            .customFont(.body)
                            .padding(4)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                switch viewModel.pendingPairingAlert {
                case .requestPending(let hostname):
                    CustomAlertView(title: pairingAlertTitle,
                                     message: String(format: "server.page.pairing.request.message".localized, hostname)) {
                        HStack {
                            Button {
                                viewModel.declineIncomingPairingRequest()
                            } label: {
                                Text("server.page.pairing.request.decline.button.label")
                                    .customFont(.body)
                                    .padding(4)
                            }
                            Button {
                                viewModel.acceptIncomingPairingRequest()
                            } label: {
                                Text("server.page.pairing.request.accept.button.label")
                                    .customFont(.body)
                                    .padding(4)
                            }
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                case .accepted:
                    CustomAlertView(title: pairingAlertTitle,
                                    message: "server.page.pairing.code.alert.message".localized) {
                        VStack {
                            CodeVerificationFieldView(code: .constant(viewModel.randomCode), readOnly: true)
                                .padding(.bottom, 16)
                            Button {
                                viewModel.cancelAcceptedPairingRequest()
                            } label: {
                                Text("server.page.pairing.code.alert.cancel.button.label")
                                    .customFont(.body)
                                    .padding(4)
                            }
                            .keyboardShortcut(.cancelAction)
                        }
                    }
                case .none:
                    EmptyView()
                }
            }
        }
    }
}

#Preview {
    ServerView(action: {_ in })
        .frame(width: 812, height: 600)
}
