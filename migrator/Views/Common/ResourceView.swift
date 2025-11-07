//
//  ResourceView.swift
//  IBM Data Shift
//
//  Created on 07/10/2025.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI
import WebKit

/// A SwiftUI view that presents a resource (such as a remote privacy policy or local external document) in a modal window using a web view.
///
/// The view shows a header with the specified title and a close button. The main content area displays the remote resource in a web view,
/// with a loading indicator shown while the content is loading. If loading fails, an error message with a retry button is displayed.
struct ResourceView: View {

    // MARK: - Environment Variables
    
    /// Controls whether this view is currently presented, and provides an interface for dismissing it.
    @Environment(\.presentationMode) var presentationMode
    
    // MARK: - State Variables
    
    /// A Boolean state indicating whether the web resource is currently loading.
    @State private var isLoading: Bool = true
    /// A Boolean state indicating whether an error occurred while loading the web resource.
    @State private var loadingError: Bool = false
    /// A Boolean state that controls the presentation of the confirmation alert.
    @State private var showConfirmation: Bool = false
    
    // MARK: - Public Constants
    
    /// The title displayed at the top of the modal resource view.
    let title: String
    /// The URL of the remote resource to display in the web view.
    let resource: URL
    /// A Boolean flag that determines whether the view must collect explicit user acceptance before allowing dismissal.
    let requireUserAcceptance: Bool
    /// The UserDefaults key used to persist the user's acceptance decision when `requireUserAcceptance` is true.
    let acceptanceDefaultsKey: String
    /// The localized message displayed within the confirmation alert when user acceptance is required.
    let acceptanceMessageLabel: String
    
    // MARK: - Intitializers
    
    init(title: String, resource: URL, requireUserAcceptance: Bool = false, acceptanceDefaultsKey: String = "", acceptanceMessageLabel: String = "") {
        self.title = title
        self.resource = resource
        self.requireUserAcceptance = requireUserAcceptance
        self.acceptanceDefaultsKey = acceptanceDefaultsKey
        self.acceptanceMessageLabel = acceptanceMessageLabel
    }
    
    // MARK: - Views
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                    .padding(.leading)
                Spacer()
                if !requireUserAcceptance {
                    Button("remote.resource.view.button.close.label") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .padding(.trailing)
                }
            }
            .padding(.vertical, 12)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
            Spacer(minLength: 0)
            ZStack {
                if isLoading {
                    ProgressView("remote.resource.view.loading.label")
                        .padding()
                }
                if loadingError {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        Text(String(format: "remote.resource.view.error.loading.label".localized, resource.absoluteString))
                            .font(.title2)
                        Text("remote.resource.view.error.hint.label")
                            .foregroundColor(.secondary)
                        Button("remote.resource.view.error.retry.button.label") {
                            isLoading = true
                            loadingError = false
                        }
                        .padding()
                    }
                    .padding()
                } else {
                    WebView(url: resource) { success in
                        isLoading = false
                        loadingError = !success
                    }
                    .padding(1)
                }
            }
            if requireUserAcceptance {
                HStack {
                    Button("resource.view.acceptance.checkbox.disagree.button.label") {
                        self.showConfirmation.toggle()
                    }
                    .keyboardShortcut(.cancelAction)
                    .padding(.leading)
                    Spacer()
                    Button("resource.view.acceptance.checkbox.agree.button.label") {
                        self.showConfirmation.toggle()
                    }
                    .keyboardShortcut(.defaultAction)
                    .padding(.trailing)
                }
                .padding(.vertical, 12)
                .frame(height: 44)
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            }
            Spacer(minLength: 0)
        }
        .frame(width: 700, height: 600)
        .alert(isPresented: $showConfirmation) {
            Alert(title: Text("resource.view.acceptance.alert.title"),
                  message: Text(acceptanceMessageLabel.localized),
                  primaryButton:.default(Text("resource.view.acceptance.checkbox.agree.button.label"), action: {
                UserDefaults.standard.set(true, forKey: acceptanceDefaultsKey)
                presentationMode.wrappedValue.dismiss()
            }),
                  secondaryButton: .destructive(Text("resource.view.acceptance.checkbox.disagree.button.label"), action: {
                exit(0)
            }))
        }
    }
}

struct PrivacyPolicyView_Previews: PreviewProvider {
    static var previews: some View {
        ResourceView(title: "Title", resource: URL(string: "https://www.ibm.com/privacy")!)
    }
}
