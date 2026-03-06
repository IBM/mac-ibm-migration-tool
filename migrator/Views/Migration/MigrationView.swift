//
//  MigrationView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 16/11/2023.
//  © Copyright IBM Corp. 2023, 2026
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
            CustomizableIconView(pageIdentifier: "migration")
                .padding(.top, 55)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            Text(viewModel.migrationProgress == 1 ? "migration.page.title.complete.label".localized : "migration.page.title.ongoing.label".localized)
                .multilineTextAlignment(.center)
                .customFont(size: 27, weight: .bold)
                .padding(.bottom, 8)
            Text(viewModel.migrationProgress == 1 ? "migration.page.body.source.complete.label".localized : "migration.page.body.ongoing.label".localized)
                .multilineTextAlignment(.center)
                .customFont(.body)
                .padding(.horizontal, 40)
            Image("new_mac")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 90, height: 90)
                .tint(Color("uiIcon"))
                .accessibilityHidden(true)
            HStack(spacing: 0) {
                Text(viewModel.migrationProgress == 1 ? "migration.page.progressbar.top.complete.label".localized : "migration.page.progressbar.top.ongoing.label".localized)
                    .customFont(.body)
                Text(viewModel.migrationController.hostName).customFont(style: .body, weight: .bold)
                Text(viewModel.usedInterface)
                    .customFont(.body)
            }
            .padding(.vertical, 4)
            VStack {
                ProgressView(value: viewModel.migrationProgress == 0 ? nil : viewModel.migrationProgress)
                    .progressViewStyle(.linear)
                    .controlSize(.regular)
                HStack {
                    Text(viewModel.estimatedTimeLeft)
                        .customFont(.callout)
                    Spacer()
                    Text(viewModel.percentageCompleted)
                        .customFont(.callout)
                }
            }
            .padding(.horizontal, 176)
            Spacer()
            Button(action: {
                NSWorkspace.shared.open(MigrationReportController.shared.reportURL)
            }, label: {
                HStack {
                    Image(systemName: "doc.fill")
                    Text("final.page.report.button.label")
                        .customFont(.body)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
            })
            .buttonStyle(.link)
            .padding(.bottom, 16)
            .hiddenConditionally(isHidden: viewModel.migrationProgress < 1 ? true : !AppContext.shouldGenerateReport)
            Divider()
            HStack {
                if !viewModel.deviceIsConnectedToPower {
                    Button {
                        showWarningPopover.toggle()
                    } label: {
                        Image(systemName: "exclamationmark")
                    }
                    .clipShape(Circle())
                    .accessibilityHint("accessibility.migrationView.warningButton.hint")
                    .popover(isPresented: $showWarningPopover, arrowEdge: .bottom) {
                        Text("migration.page.warning.button.popover.text")
                            .customFont(.body)
                            .padding()
                    }
                }
                Spacer()
                Button(action: {
                    appDelegate.quit()
                }, label: {
                    Text("migration.page.main.button.label")
                        .customFont(.body)
                        .padding(4)
                })
                .hiddenConditionally(isHidden: viewModel.migrationProgress < 1)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("accessibility.migrationView.mainButton.hint")
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
        }
        .task {
            self.viewModel.startMigration()
        }
        .overlay {
            if viewModel.connectionInterrupted {
                CustomAlertView(title: "connection.error.alert.title".localized, message: "connection.error.alert.restoring.message".localized) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.regular)
                }
            }
        }
    }
}

#Preview {
    MigrationView(action: { _ in })
        .frame(width: 812, height: 600)
}
