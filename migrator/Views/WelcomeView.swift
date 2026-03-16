//
//  WelcomeView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 16/11/2023.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// Struct representing the WelcomeView page.
struct WelcomeView: View {
    
    // MARK: - Environment Variables
    
    @Environment(\.colorScheme) var colorScheme
    
    // MARK: - Constants
    
    /// Closure to execute when an action is taken that requires navigation
    let action: (MigratorPage) -> Void
    
    // MARK: - Variables
    
    var appName: String {
        return Bundle.main.name
    }
    
    // MARK: - State Variables
    
    /// State to keep track of the next page to navigate to
    @State private var nextPage: MigratorPage = .welcome
    /// State to control the visibility of FDA error messages
    @State private var showFDAError: Bool = false
    /// State to control the visibility of Management error messages
    @State private var showManagementError: Bool = false

    @State private var showTermsAndConditions: Bool = false
    
    @State private var showPrivacyPolicy: Bool = false
    
    // MARK: - Views
    
    var body: some View {
        VStack {
            CustomizableIconView(pageIdentifier: "welcome")
                .padding(.top, 55)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            Text(String(format: "welcome.page.title".localized, Bundle.main.name))
                .multilineTextAlignment(.center)
                .customFont(size: 27, weight: .bold)
                .padding(.bottom, 8)
            Text("welcome.page.subtitle")
                .multilineTextAlignment(.center)
                .customFont(.body)
                .padding(.bottom)
                .padding(.horizontal, 40)
            HStack(spacing: 15) {
                CardButton(image: Image("new_mac"),
                           label: "welcome.page.button.big.left.label".localized,
                           action: {
                    action(.server)
                })
                .frame(width: 200)
                .accessibilityLabel("accessibility.welcomePage.leftButton.label")
                .accessibilityHint("accessibility.welcomePage.leftButton.hint")
                CardButton(image: Image("old_mac"),
                           label: "welcome.page.button.big.right.label".localized,
                           action: {
                    action(.browser)
                })
                .frame(width: 200)
                .accessibilityLabel("accessibility.welcomePage.rightButton.label")
                .accessibilityHint("accessibility.welcomePage.rightButton.hint")
            }
            Spacer()
            Divider()
            HStack(spacing: 2) {
                if AppContext.shouldShowWelcomePageInfo {
                    versionCopyrightPrivacy
                }
                Spacer()
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
            .frame(height: 56)
        }
        .alert("welcome.page.fda.error.title", isPresented: $showFDAError, actions: {
            Button(action: {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                exit(0)
            }, label: {
                Text(String(format: "welcome.page.fda.error.first.action.title".localized, Utils.Common.systemSettingsLabel))
                    .customFont(.body)
            })
            .accessibilityHint("accessibility.welcomePage.fdaAlert.defaultButton.hint")
            Button {
                exit(0)
            } label: {
                Text("welcome.page.fda.error.second.action.title")
                    .customFont(.body)
            }
            .accessibilityHint("accessibility.welcomePage.fdaAlert.secondaryButton.hint")
        }, message: {
            Text(String(format: "welcome.page.fda.error.message".localized,
                        appName,
                        String(format: "welcome.page.fda.error.first.action.title".localized, Utils.Common.systemSettingsLabel),
                        appName))
                .customFont(.body)
        })
        .alert(String(format: "welcome.page.management.error.title".localized, AppContext.orgName), isPresented: $showManagementError, actions: {
            Button(action: {
                NSWorkspace.shared.open(URL(string: AppContext.enrollmentRedirectionLink)!)
                exit(0)
            }, label: {
                Text("welcome.page.management.error.first.action.title")
                    .customFont(.body)
            })
            .accessibilityHint("accessibility.welcomePage.mdmAlert.defaultButton.hint")
        }, message: {
            Text(String(format: "welcome.page.management.error.message".localized, Bundle.main.name, AppContext.orgName, AppContext.orgName))
                .customFont(.body)
        })
        .sheet(isPresented: $showTermsAndConditions) {
            ResourceView(title: "common.app.menu.label.termsandconditon".localized,
                         resource: AppContext.termsConditionsURL!,
                         requireUserAcceptance: true,
                         acceptanceDefaultsKey: AppContext.tAndCUserAcceptanceKey,
                         acceptanceMessageLabel: "welcome.page.termsandconditions.message.label")
                .frame(width: 700, height: 600)
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            ResourceView(title: "common.app.menu.label.privacypolicy".localized, resource: AppContext.privacyPolicyURL!)
                .frame(width: 700, height: 600)
        }
        .task {
            if !AppContext.userAcceptedTermsAndConditions && AppContext.shouldRequireTAndCAcceptance {
                self.showTermsAndConditions.toggle()
            }
            // Trying to access a file unaccessible without Full Disk Access permissions as there isn't a way to ask for those permission with an API. This trick allow the app to be in the Full Disk Access app list.
#if !DEBUG
            try? FileManager.default.copyItem(atPath: "/Library/Preferences/com.apple.TimeMachine.plist", toPath: "/private/tmp/com.apple.TimeMachine.plist")
            // If the app is not able to read at this path it means that it doesn't have FDA permissions so an alert is showed to ask the user to allow it.
            if !FileManager.default.isReadableFile(atPath: "/Library/Preferences/com.apple.TimeMachine.plist") {
                showFDAError.toggle()
            }
#endif
            if !AppContext.shouldSkipMDMCheck {
                switch DeviceManagementHelper.shared.state {
                case .unmanaged, .unknown, .managedByUnknownOrg, .none:
                    showManagementError.toggle()
                case .managed:
                    break
                }
            }
            
        }
    }
    
    var versionCopyrightPrivacy: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !Bundle.main.marketingVersion.isEmpty && !Bundle.main.buildNumber.isEmpty {
                Text(String(format: "welcome.page.bundle.version.label".localized, Bundle.main.marketingVersion, Bundle.main.buildNumber))
                    .customFont(.caption)
                    .alignmentGuide(.firstTextBaseline) { $0[.firstTextBaseline] }
            }
            if !Bundle.main.copyright.isEmpty {
                Text(Bundle.main.copyright)
                    .customFont(.caption)
                    .alignmentGuide(.firstTextBaseline) { $0[.firstTextBaseline] }
            }
            if AppContext.privacyPolicyURL != nil {
                Button(action: {
                    self.showPrivacyPolicy.toggle()
                }, label: {
                    Text("common.app.menu.label.privacypolicy")
                        .customFont(.caption)
                })
                .buttonStyle(.link)
                .alignmentGuide(.firstTextBaseline) { $0[.firstTextBaseline] }
            }
        }
    }
}

#Preview {
    WelcomeView(action: {_ in })
    .frame(width: 812, height: 600)
}
