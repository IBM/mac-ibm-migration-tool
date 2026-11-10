//
//  CustomAlertView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 14/02/2025.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

struct CustomAlertView<Content: View>: View {
    
    // MARK: - Public Variables
    
    var title: String
    var message: String?
    @ViewBuilder var content: Content
    
    // MARK: - Views
    
    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            Text(title)
                .customFont(.title2, weight: .semibold)
                .frame(maxWidth: 400)
                .padding(.vertical, 4)
            if let message = message {
                Text(message)
                    .customFont(.body)
                    .frame(maxWidth: 400)
                    .padding(.bottom, 8)
            }
            content
        }
        .padding(30)
        .background {
            if #available(macOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular, in: .rect(cornerRadius: 30))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.windowBackgroundColor.withAlphaComponent(0.8)))
                    .shadow(radius: 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    CustomAlertView(title: "Test Title", message: "Test Message", content: {
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(.regular)
    })
        .frame(width: 812, height: 600)
}
