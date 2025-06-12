//
//  CustomAlertView.swift
//  migrator
//
//  Created by Simone Martorelli on 14/02/2025.
//  Copyright © 2025 IBM. All rights reserved.
//

import SwiftUI

struct CustomAlertView<Content: View>: View {
    
    // MARK: - Public Variables
    
    var title: String
    var message: String?
    @ViewBuilder var content: Content
    
    // MARK: - Views
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color("discoveryViewBackground"))
                            .shadow(color: Color(red: 0, green: 0, blue: 0, opacity: 0.15), radius: 6, x: 0, y: 0)
                        VStack {
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
                        .padding(32)
                    }
                    .fixedSize()
                    Spacer()
                }
                Spacer()
            }
            
        }
    }
}

#Preview {
    CustomAlertView(title: " Test Title", message: "Test Message", content: {
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(.regular)
    })
        .frame(width: 812, height: 600)
}
