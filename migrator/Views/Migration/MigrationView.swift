//
//  MigrationView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 16/11/2023.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// Struct representing the Migration view.
struct MigrationView: View {
    
    // MARK: - Constants
    
    /// Closure to execute when an action requires navigation to a different page.
    let action: (MigratorPage) -> Void
    
    // MARK: - Environment Variables

    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject private var appDelegate: AppDelegate

    // MARK: - State Variables
    
    /// State variable to track warning popover appearance.
    @State private var showWarningPopover: Bool = true
    
    // MARK: - Observed Variables
    
    /// Observable view model object to handle data and logic for the server view
    @ObservedObject var viewModel: MigrationViewModel = MigrationViewModel()
    
    // MARK: - Views
    
    var body: some View {
        VStack {
            Image("icon")
                .resizable()
                .frame(width: 86, height: 86)
                .padding(.top, 55)
                .padding(.bottom, 8)
            Text(viewModel.migrationProgress == 1 ? "migration.page.title.complete.label".localized : "migration.page.title.ongoing.label".localized)
                .multilineTextAlignment(.center)
                .font(.system(size: 27, weight: .bold))
                .padding(.bottom, 8)
            Text(viewModel.migrationProgress == 1 ? "migration.page.body.source.complete.label".localized : "migration.page.body.ongoing.label".localized)
                .multilineTextAlignment(.center)
                .padding(.bottom)
                .padding(.horizontal, 40)
            Image("new_mac")
                .padding(.vertical, 4)
            Group {
                Text(viewModel.migrationProgress == 1 ? "migration.page.progressbar.top.complete.label".localized : "migration.page.progressbar.top.ongoing.label".localized) + Text(viewModel.migrationController.hostName).fontWeight(.bold) + Text(viewModel.usedInterface)
            }
            .padding(.vertical, 4)
            VStack {
                ProgressView(value: viewModel.migrationProgress == 0 ? nil : viewModel.migrationProgress)
                    .progressViewStyle(.linear)
                    .controlSize(.regular)
                HStack {
                    Text(viewModel.estimatedTimeLeft)
                        .font(.callout)
                    Spacer()
                    Text(viewModel.percentageCompleted)
                        .font(.callout)
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
                Button(action: {
                    appDelegate.quit()
                }, label: {
                    Text("migration.page.main.button.label")
                        .padding(4)
                })
                .hiddenConditionally(isHidden: viewModel.migrationProgress < 1)
                .keyboardShortcut(.defaultAction)
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
        }
    }
}

#Preview {
    MigrationView(action: { _ in })
        .frame(width: 812, height: 600)
}
