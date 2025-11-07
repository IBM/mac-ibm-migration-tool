//
//  MigratorPage.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 16/11/2023.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// Enum representing different pages in the migration process.
enum MigratorPage: CaseIterable {
    case welcome
    case browser
    case codeVerification
    case server
    case migrationSetup
    case recap
    case migration
    case appleID
    case recon
    case reboot
    case final
    
    /// Generates a SwiftUI view for the corresponding page.
    /// - Parameter action: A closure to handle actions triggered within the views.
    /// - Returns: A SwiftUI view representing the page.
    @ViewBuilder
    func view(action: @escaping (MigratorPage) -> Void) -> some View {
        switch self {
        case .welcome:
            WelcomeView(action: action)
        case .browser:
            BrowserView(action: action)
        case .codeVerification:
            CodeVerificationView(action: action)
        case .server:
            ServerView(action: action)
        case .migrationSetup:
            MigrationSetupView(action: action)
        case .recap:
            RecapView(action: action)
        case .migration:
            MigrationView(action: action)
        case .appleID:
            AppleIDView(action: action)
        case .recon:
            JamfReconView(action: action)
        case .reboot:
            RebootView(action: action)
        case .final:
            FinalView()
        }
    }
    
    func next() -> MigratorPage {
        switch self {
        case .server:
            if !AppContext.shouldSkipAppleIDCheck && !Utils.FileManagerHelpers.iCloudAvailable {
                return .appleID
            } else {
                fallthrough
            }
        case .appleID:
            if !AppContext.shouldSkipDeviceReboot {
                return .reboot
            } else {
                fallthrough
            }
        case .reboot:
            if !AppContext.shouldSkipJamfRecon {
                return Utils.Common.reconPage
            } else {
                fallthrough
            }
        case .recon:
            return .final
        default:
            return .welcome
        }
    }
}
