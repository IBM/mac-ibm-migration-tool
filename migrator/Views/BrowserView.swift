//
//  BrowserView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 14/12/2023.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// Struct representing the page to visualize the Browser behaviour.
struct BrowserView: View {
    
    // MARK: - Environment Variables

    @Environment(\.colorScheme) var colorScheme
    
    // MARK: - Constants
    
    /// Closure to execute when an action requires navigation to a different page.
    let action: (MigratorPage) -> Void
    /// The previous page to navigate back to, by default set to the welcome page.
    let previousPage: MigratorPage = .welcome
    /// The next page to navigate forward to, typically the migration setup page.
    let nextPage: MigratorPage = .codeVerification
    
    // MARK: - Observable Variables
    
    /// Observable object to control and observe migration browser-related activities.
    @ObservedObject var migrationController: MigrationController = MigrationController.shared
    
    // MARK: - State Variables
    
    /// State variable that store the selected network device result from the browsing action.
    @State private var selectedResult: NetworkDevice?

    // MARK: - Initializers
    
    /// Custom initializer to set up the view with a navigation action and start the browsing process.
    /// - Parameter action: the navigation action.
    init(action: @escaping (MigratorPage) -> Void) {
        self.action = action
        // Starts the browsing process as soon as the view is initialized.
        migrationController.startBrowser()
    }
    
    // MARK: - Views
    
    var body: some View {
        VStack {
            CustomizableIconView(pageIdentifier: "browser")
                .padding(.top, 55)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            Text("browser.page.title")
                .multilineTextAlignment(.center)
                .font(.system(size: 27, weight: .bold))
                .padding(.bottom, 8)
            Text("browser.page.subtitle")
                .multilineTextAlignment(.center)
                .padding(.bottom)
                .padding(.horizontal, 40)
            deviceList
                .padding(.horizontal, 270)
                .padding(.bottom, 4)
                .accessibilityElement(children: .contain)
            Spacer()
            Text(String(format: "browser.page.reminder.label".localized, Bundle.main.name, "welcome.page.button.big.left.label".localized))
                .padding(.bottom, 4)
                .multilineTextAlignment(.center)
            Divider()
            HStack {
                Spacer()
                Button(action: {
                    didPressSecondaryButton()
                }, label: {
                    secondaryButtonLabel
                })
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .accessibilityHint("accessibility.browserPage.secondayButton.hint")
                ZStack {
                    Button(action: {
                        didPressMainButton()
                    }, label: {
                        mainButtonLabel
                    })
                    .buttonStyle(.bordered)
                    .disabled(selectedResult == nil)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint("accessibility.browserPage.mainButton.hint")
                }
                .padding(.leading, 6)
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
        }
    }
    
    var deviceList: some View {
        ZStack {
            Color("discoveryViewBackground")
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: Color(red: 0, green: 0, blue: 0, opacity: 0.15), radius: 6, x: 0, y: 0)
                .accessibilityHidden(true)
            VStack(alignment: .center) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .padding(.top, 10)
                    .accessibilityHidden(true)
                List($migrationController.browserResults, id: \.self, selection: $selectedResult) { result in
                    DeviceListRow(result: result)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(result.name.wrappedValue)
                }
                .onChange(of: migrationController.browserResults) { newResults in
                    if !newResults.contains(where: { $0.id == selectedResult?.id }) {
                        selectedResult = nil
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("accessibility.browserPage.deviceTable.label")
                .padding(.top, 0)
                .padding(.bottom, 8)
                .padding(.horizontal, 2)
                Spacer()
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
        if let result = selectedResult?.browserResult {
            migrationController.selectedBrowserResult = result
            action(nextPage)
        }
    }
    
    private func didPressSecondaryButton() {
        migrationController.stopBrowser()
        action(previousPage)
    }
}

#Preview {
    BrowserView(action: { _ in })
        .frame(width: 812, height: 600)
}
