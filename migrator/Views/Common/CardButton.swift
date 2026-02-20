//
//  CardButton.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 10/11/2025.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// A customizable card-style button with an icon, label, and action indicator.
/// Features a press animation effect that scales and highlights the button on interaction.
struct CardButton: View {
    
    // MARK: - Variables
    
    /// The main icon displayed in the card
    var image: Image
    /// The text label describing the button's action
    var label: String
    /// The action to perform when the button is tapped
    var action: () -> Void
    /// The height of the main icon (default: 40)
    var imageHeight: CGFloat = 40
    /// The action indicator icon displayed on the right (default: arrow.right)
    var actionImage: Image = Image(systemName: "arrow.right")
    /// The color used for the action icon (default: accent color)
    var accentColor: Color = .accentColor
    /// The tint color applied to the main icon (default: uiIcon)
    var tintColor: Color = Color("uiIcon")
    
    // MARK: - Views
    
    var body: some View {
        Button(action: {
            action()
        }, label: {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading) {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: imageHeight)
                        .tint(tintColor)
                    Spacer()
                    Text(label)
                        .customFont(size: 14, weight: .regular)
                }
                .padding([.leading, .top, .bottom], 12)
                Spacer()
                actionImage
                    .font(.system(size: 14))
                    .foregroundStyle(accentColor)
                    .padding(12)
            }
            .background {
                if #available(macOS 26.0, *) {
                    Color("bigButtonUnselected")
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Color("bigButtonUnselected")
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        })
        .buttonStyle(CardButtonStyle())
        .shadow(color: Color(red: 0, green: 0, blue: 0, opacity: 0.3), radius: 2.5, x: 0, y: 0.5)
        .aspectRatio(1.66, contentMode: .fit)
    }
}

// MARK: - Button Style

/// Custom button style that provides visual feedback on press.
/// Applies a scale effect, accent color overlay, and smooth spring animation.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(configuration.isPressed ? Color.accentColor.opacity(0.30) : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
