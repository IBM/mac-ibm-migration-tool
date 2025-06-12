//
//  MainView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 16/11/2023.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// Scruct representing the MainView of the App.
struct MainView: View {
    
    // MARK: - State Variables
    
    /// State variable to keep track of the current page in the view
    @State private var currentPage: MigratorPage = .welcome
    
    // MARK: - Initializers
    
    init() {
        if AppContext.isPostRebootPhase {
            _currentPage = State(initialValue: .reboot.next())
        }
    }
    
    // MARK: - Views
    
    var body: some View {
        currentPage.view(action: { nextPage in
            currentPage = nextPage
        })
        .frame(width: 812, height: 600)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    MainView()
}
