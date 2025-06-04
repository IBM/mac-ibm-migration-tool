//
//  WelcomeView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 16/11/2023.
//  © Copyright IBM Corp. 2023, 2024
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
    
    // MARK: - Views
    
    var body: some View {
        VStack {
            Image("icon")
                .resizable()
                .frame(width: 86, height: 86)
                .padding(.top, 55)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            Text(String(format: "welcome.page.title".localized, Bundle.main.name))
                .multilineTextAlignment(.center)
                .font(.system(size: 27, weight: .bold))
                .padding(.bottom, 8)
            Text("welcome.page.subtitle")
                .multilineTextAlignment(.center)
                .padding(.bottom)
                .padding(.horizontal, 40)
            HStack(spacing: 86) {
                VStack {
                    Button(action: {
                        nextPage = .server
                    }, label: {
                        Image("new_mac")
                            .frame(width: 120, height: 120)
                            .background(content: {
                                // Change background based on selection
                                if nextPage == .server {
                                    LinearGradient.bigButtonSelected(colorScheme: colorScheme)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    Color("bigButtonUnselected")
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            })
                    })
                    .buttonStyle(.plain)
                    .shadow(color: Color(red: 0, green: 0, blue: 0, opacity: 0.3), radius: 2.5, x: 0, y: 0.5)
                    .padding(.bottom, 6)
                    .accessibilityLabel("accessibility.welcomePage.leftButton.label")
                    .accessibilityHint("accessibility.welcomePage.leftButton.hint")
                    Text("welcome.page.button.big.left.label")
                        .accessibilityHidden(true)
                }
                VStack {
                    Button(action: {
                        nextPage = .browser
                    }, label: {
                        Image("old_mac")
                            .frame(width: 120, height: 120)
                            .background(content: {
                                // Change background based on selection
                                if nextPage == .browser {
                                    LinearGradient.bigButtonSelected(colorScheme: colorScheme)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    Color("bigButtonUnselected")
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            })
                    })
                    .buttonStyle(.plain)
                    .shadow(color: Color.black.opacity(0.3), radius: 2.5, x: 0, y: 0.5)
                    .padding(.bottom, 6)
                    .accessibilityLabel("accessibility.welcomePage.rightButton.label")
                    .accessibilityHint("accessibility.welcomePage.rightButton.hint")
                    Text("welcome.page.button.big.right.label")
                        .accessibilityHidden(true)
                }
            }
            Spacer()
            Divider()
            HStack {
                Spacer()
                Button(action: {
                    action(nextPage)
                }, label: {
                    Text("welcome.page.button.main.label")
                        .padding(4)
                })
                .disabled(nextPage == .welcome)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("accessibility.welcomePage.mainButton.hint")
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
        }
        .alert("welcome.page.fda.error.title", isPresented: $showFDAError, actions: {
            Button(action: {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                exit(0)
            }, label: {
                Text(String(format: "welcome.page.fda.error.first.action.title".localized, Utils.systemSettingsLabel))
            })
            .accessibilityHint("accessibility.welcomePage.fdaAlert.defaultButton.hint")
            Button {
                exit(0)
            } label: {
                Text("welcome.page.fda.error.second.action.title")
            }
            .accessibilityHint("accessibility.welcomePage.fdaAlert.secondaryButton.hint")
        }, message: {
            Text(String(format: "welcome.page.fda.error.message".localized, appName, Utils.systemSettingsLabel, appName))
        })
        .alert(String(format: "welcome.page.management.error.title".localized, AppContext.orgName), isPresented: $showManagementError, actions: {
            Button(action: {
                NSWorkspace.shared.open(URL(string: AppContext.enrollmentRedirectionLink)!)
                exit(0)
            }, label: {
                Text("welcome.page.management.error.first.action.title")
            })
            .accessibilityHint("accessibility.welcomePage.mdmAlert.defaultButton.hint")
        }, message: {
            Text(String(format: "welcome.page.management.error.message".localized, AppContext.orgName, AppContext.orgName))
        })
        .onAppear {
            // Trying to access a file unaccessible without Full Disk Access permissions as there isn't a way to ask for those permission with an API. This trick allow the app to be in the Full Disk Access app list.
            #if !DEBUG
            try? FileManager.default.copyItem(atPath: "/Library/Preferences/com.apple.TimeMachine.plist", toPath: "/private/tmp/com.apple.TimeMachine.plist")
            // If the app is not able to read at this path it means that it doesn't have FDA permissions so an alert is showed to ask the user to allow it.
            if !FileManager.default.isReadableFile(atPath: "/Library/Preferences/com.apple.TimeMachine.plist") {
                showFDAError.toggle()
            }
            if !AppContext.shouldSkipMDMCheck {
                switch DeviceManagementHelper.shared.state {
                case .unmanaged, .unknown, .managedByUnknownOrg:
                    showManagementError.toggle()
                case .managed:
                    break
                }
            }
            #endif
        }
    }
}

#Preview {
    WelcomeView(action: {_ in })
    .frame(width: 812, height: 600)
}
