//
//  View-Extension.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 05/01/2024.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

extension View {
    /// Conditionally hides the view based on a Boolean flag.
    /// - Parameter isHidden: A Boolean value that determines whether the view should be hidden.
    /// - Returns: A view that is either hidden or visible based on the `isHidden` parameter.
    func hiddenConditionally(isHidden: Bool) -> some View {
        if isHidden {
            return AnyView(self.hidden())
        } else {
            return AnyView(self)
        }
    }
    
    /// Applies a custom font with the specified weight and size
    /// - Parameters:
    ///   - weight: The font weight to use (default: .regular)
    ///   - size: The font size
    /// - Returns: A view with the custom font applied
    func customFont(weight: FontManager.FontWeight = .regular, size: CGFloat) -> some View {
        self.font(FontManager.shared.font(weight: weight, size: size))
    }
    
    /// Applies a custom font matching system font with size and weight
    /// - Parameters:
    ///   - size: The font size
    ///   - weight: The SwiftUI font weight (default: .regular)
    /// - Returns: A view with the custom font applied
    func customFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        let customWeight = FontManager.shared.fontWeight(from: weight)
        return self.font(FontManager.shared.font(weight: customWeight, size: size))
    }
    
    /// Applies a custom font with a predefined text style using Dynamic Type
    /// - Parameters:
    ///   - style: The text style to use (e.g., .title, .body, .caption)
    ///   - weight: The font weight to use (default: .regular)
    /// - Returns: A view with the custom font applied with Dynamic Type support
    func customFont(style: Font.TextStyle, weight: FontManager.FontWeight = .regular) -> some View {
        self.font(FontManager.shared.font(style: style, weight: weight))
    }
    
    /// Applies a custom font with a predefined text style and SwiftUI weight using Dynamic Type
    /// - Parameters:
    ///   - style: The text style to use (e.g., .title, .body, .caption)
    ///   - weight: The SwiftUI font weight (default: .regular)
    /// - Returns: A view with the custom font applied with Dynamic Type support
    func customFont(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> some View {
        let customWeight = FontManager.shared.fontWeight(from: weight)
        return self.font(FontManager.shared.font(style: style, weight: customWeight))
    }
}
