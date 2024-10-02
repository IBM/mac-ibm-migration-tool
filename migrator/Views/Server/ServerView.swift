//
//  DiscoveryView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 14/11/2023.
//  Copyright © 2023 IBM Inc. All rights reserved
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
    
    /// State variable to track warning popover appearance.
    @State private var showWarningPopover: Bool = true
    
    // MARK: - Initializers
    
    /// Custom initializer to set up the view with a navigation action and start the listening process.
    /// - Parameter action: the navigation action.
    init(action: @escaping (MigratorPage) -> Void) {
        self.action = action
    }
      
    // MARK: - Views
    
    var body: some View {
        VStack {
            Image("icon")
                .resizable()
                .frame(width: 86, height: 86)
                .padding(.top, 55)
                .padding(.bottom, 8)
            Text(viewModel.connectionEstablished ? (viewModel.migrationProgress > 0 ? (viewModel.migrationProgress == 1 ? "server.page.title.migration.complete.label" : "server.page.title.migration.ongoing.label") : "server.page.connected.title") : "server.page.title")
                .multilineTextAlignment(.center)
                .font(.system(size: 27, weight: .bold))
                .padding(.bottom, 8)
            Text(viewModel.connectionEstablished ? (viewModel.migrationProgress > 0 ? (viewModel.migrationProgress == 1 ? "server.page.body.migration.complete.label" : "server.page.body.ongoing.label") :  "server.page.connected.subtitle") : "server.page.subtitle")
                .multilineTextAlignment(.center)
                .padding(.bottom)
                .padding(.horizontal, 40)
            Image(viewModel.connectionEstablished ? "old_mac" : "new_mac")
            if viewModel.connectionEstablished {
                Group {
                    Text(viewModel.migrationProgress == 1 ? "migration.page.progressbar.top.complete.label".localized : "migration.page.progressbar.top.ongoing.label".localized) + Text(migrationController.hostName).fontWeight(.bold) + Text(viewModel.usedInterface)
                }
                .padding(.vertical, 4)
            } else {
                Text(Host.current().localizedName ?? "server.page.default.device.name")
                    .font(.headline)
                    .padding(.vertical, 4)
            }
            VStack {
                if viewModel.connectionEstablished {
                    if viewModel.migrationProgress == 0 {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .controlSize(.regular)
                    } else {
                        ProgressView(value: viewModel.migrationProgress)
                            .progressViewStyle(.linear)
                            .controlSize(.regular)
                            
                    }
                    HStack {
                        Spacer()
                        Text("\(viewModel.percentageCompleted)")
                            .font(.callout)
                    }
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                        Spacer()
                        Text("server.page.pairing.code.label")
                            .font(.title3)
                        CodeVerificationFieldView(code: .constant(viewModel.randomCode), viewOnly: true)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 176)
            Spacer()
            Divider()
            HStack {
                if !viewModel.deviceIsConnectedToPower {
                    Button {
                        showWarningPopover.toggle()
                    } label: {
                        Image(systemName: "exclamationmark")
                    }
                    .clipShape(Circle())
                    .popover(isPresented: $showWarningPopover, arrowEdge: .bottom, content: {
                        Text("migration.page.warning.button.popover.text")
                            .padding()
                    })
                }
                Spacer()
                if viewModel.connectionEstablished {
                    Button(action: {
                        action(.server.next())
                    }, label: {
                        Text("server.page.button.main.continue.label")
                            .padding(4)
                    })
                    .disabled(viewModel.migrationProgress != 1)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(action: {
                        migrationController.stopServer()
                        action(previousPage)
                    }, label: {
                        Text("server.page.button.main.label")
                            .foregroundColor(Color.red)
                            .padding(4)
                    })
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
        }
        .alert("connection.error.alert.unrecoverable.title", isPresented: $viewModel.connectionInterrupted) {
            Button("connection.error.alert.unrecoverable.main.action.label") {
                Task { @MainActor in
                    self.viewModel.resetMigration()
                    self.action(.welcome)
                }
            }
        } message: {
            Text("connection.error.alert.unrecoverable.message")
        }
    }
}

#Preview {
    ServerView(action: {_ in })
        .frame(width: 812, height: 600)
}
