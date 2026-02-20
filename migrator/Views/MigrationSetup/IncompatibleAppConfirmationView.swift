//
//  IncompatibleAppConfirmationView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 21/01/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// View that displays a warning about incompatible applications being migrated
struct IncompatibleAppConfirmationView: View {
    
    // MARK: - Environment
    
    @Environment(\.dismiss) var dismiss
    
    // MARK: - Properties
    
    /// List of incompatible applications that will be migrated
    let incompatibleApps: [DiscoveredApplication]
    /// Destination device architecture
    let destinationArchitecture: AppArchitecture
    /// Callback when user confirms migration
    let onConfirm: () -> Void
    /// Callback when user wants to review selection
    let onReview: () -> Void
    /// Callback when user wants to ignore the selection and start the migration
    let onIgnore: () -> Void

    // MARK: - Computed Properties
    
    /// Determines if we're showing Intel-only apps (migrating to Apple Silicon)
    private var isIntelToSilicon: Bool {
        return destinationArchitecture == .appleSilicon
    }
    
    /// Gets the appropriate warning title based on migration direction
    private var warningTitle: String {
        return isIntelToSilicon ?
        "app.architecture.warning.title.intelToSilicon".localized :
        "app.architecture.warning.title.siliconToIntel".localized
    }
    
    private var intelToSiliconWarningMessage: String {
        return (MigrationController.shared.destinationDeviceInfo?.isRosetta2Installed ?? false) ?
        String(format: "app.architecture.warning.message.intelToSilicon.rosetta".localized, Bundle.main.name) :
        "app.architecture.warning.message.intelToSilicon.norosetta".localized
    }
    
    /// Gets the appropriate warning message based on migration direction
    private var warningMessage: String {
        return isIntelToSilicon ?
        intelToSiliconWarningMessage :
        "app.architecture.warning.message.siliconToIntel".localized
    }
    
    /// Gets the appropriate info message based on migration direction
    private var infoMessage: String {
        return isIntelToSilicon ?
        "app.architecture.warning.rosetta.info".localized :
        "app.architecture.warning.incompatible.info".localized
    }
    
    /// Gets the appropriate badge text based on migration direction
    private var badgeText: String {
        return isIntelToSilicon ?
        "app.architecture.badge.intel".localized :
        "app.architecture.badge.appleSilicon".localized
    }
    
    private var badgeHelpText: String {
        return isIntelToSilicon ?
        "app.architecture.tooltip.intel".localized :
        "app.architecture.tooltip.silicon".localized
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.orange)
                Text(warningTitle)
                    .customFont(size: 20, weight: .bold)
                Spacer()
            }
            Text(warningMessage)
                .customFont(.body)
                .foregroundColor(.secondary)
            Text(String(format: "app.architecture.applications.count".localized, incompatibleApps.count))
                .customFont(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(incompatibleApps) { app in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.migratorFile.url.fullURL().relativePath))
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text(app.name)
                                .customFont(.body)
                            Spacer()
                            Text(badgeText)
                                .customFont(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .cornerRadius(4)
                                .padding(.trailing)
                                .help(badgeHelpText)
                        }
                        .padding(.vertical, 4)
                        if app.id != incompatibleApps.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            Spacer()
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 20))
                VStack(alignment: .leading) {
                    Text(infoMessage)
                        .customFont(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if isIntelToSilicon {
                        Button(action: {
                            NSWorkspace.shared.open(URL(string: "https://support.apple.com/en-us/102527")!)
                        }, label: {
                            Text("app.architecture.doc.link.label")
                                .customFont(.callout)
                        })
                        .buttonStyle(.link)
                    }
                }
            }
            .padding(.bottom, 8)
            HStack(spacing: 12) {
                Spacer()
                Button(action: {
                    dismiss()
                    onReview()
                }, label: {
                    Text("app.architecture.confirmation.review")
                        .customFont(.body)
                        .padding(4)
                })
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                Button(action: {
                    dismiss()
                    onIgnore()
                }, label: {
                    Text("app.architecture.confirmation.ignore")
                        .customFont(.body)
                        .padding(4)
                })
                .buttonStyle(.bordered)
                Button(action: {
                    dismiss()
                    onConfirm()
                }, label: {
                    Text("app.architecture.confirmation.migrate")
                        .customFont(.body)
                        .padding(4)
                })
                .buttonStyle(.bordered)
                .keyboardShortcut(.defaultAction)
                Spacer()
            }
        }
        .padding(24)
        .frame(width: 600, height: 500)
    }
}
