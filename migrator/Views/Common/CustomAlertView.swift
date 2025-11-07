//
//  CustomAlertView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 14/02/2025.
//  © Copyright IBM Corp. 2023, 2025
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
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .fontWeight(.semibold)
                .font(.title2)
                .padding(.vertical, 4)
            if let message = message {
                Text(message)
                    .padding(.bottom, 8)
            }
            content
        }
        .padding(30)
        .background {
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.windowBackgroundColor.withAlphaComponent(0.8)))
                    .shadow(radius: 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.blur(radius: 8, opaque: true).opacity(0.3))
        .edgesIgnoringSafeArea(.all)
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
