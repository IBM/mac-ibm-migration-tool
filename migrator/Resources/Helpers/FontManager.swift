//
//  FontManager.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 04/12/2024.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI
import AppKit

/// Manager class for handling custom font loading and registration
final class FontManager {
    /// Shared singleton instance
    static let shared = FontManager()
    
    /// Available font weights for the custom font
    enum FontWeight: String, CaseIterable {
        case regular = ""
        case medium = "Medm"
        case semibold = "SmBld"
        case bold = "Bold"
        case light = "Light"
    }
    
    /// The base name of the custom font family (loaded from AppContext)
    private var customFontFamily: String {
        return AppContext.customFontFamily
    }
    
    /// Flag to track if fonts have been registered
    private var fontsRegistered = false
    
    /// Flag to indicate if custom fonts should be used
    private var shouldUseCustomFonts: Bool {
        return !customFontFamily.isEmpty
    }
    
    private init() {
        if shouldUseCustomFonts {
            registerCustomFonts()
        }
    }
    
    /// Registers all custom fonts from the Resources folder
    private func registerCustomFonts() {
        guard !fontsRegistered && shouldUseCustomFonts else { return }
        let fontWeights: [FontWeight] = FontWeight.allCases
        for weight in fontWeights {
            let fontName = "\(customFontFamily)\(weight.rawValue.isEmpty ? "" : "-\(weight.rawValue)")"
            
            // Try common font file extensions
            for ext in ["ttf", "otf"] {
                if let fontURL = Bundle.main.url(forResource: fontName, withExtension: ext) {
                    registerFont(from: fontURL)
                    break
                }
            }
        }
        fontsRegistered = true
    }
    
    /// Registers a single font file
    /// - Parameter url: The URL of the font file
    private func registerFont(from url: URL) {
        guard let fontDataProvider = CGDataProvider(url: url as CFURL),
              let font = CGFont(fontDataProvider) else {
            MLogger.main.log("Failed to load font from: \(url.lastPathComponent).", type: .fault)
            return
        }
        
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterGraphicsFont(font, &error) {
            if let error = error?.takeRetainedValue() {
                MLogger.main.log("Error registering font: \(error).", type: .fault)
            }
        }
    }
    
    /// Returns a custom font with the specified weight and size
    /// - Parameters:
    ///   - weight: The font weight to use
    ///   - size: The font size
    /// - Returns: A Font instance with the custom font, or system font as fallback
    func font(weight: FontWeight = .regular, size: CGFloat) -> Font {
        // If no custom font family is configured, use system font directly
        guard shouldUseCustomFonts else {
            let systemWeight: Font.Weight = {
                switch weight {
                case .light: return .light
                case .regular: return .regular
                case .medium: return .medium
                case .semibold: return .semibold
                case .bold: return .bold
                }
            }()
            return Font.system(size: size, weight: systemWeight)
        }
        
        let fontName = "\(customFontFamily)\(weight.rawValue.isEmpty ? "" : "-\(weight.rawValue)")"
        
        // Check if the font is available
        if NSFont(name: fontName, size: size) != nil {
            return Font.custom(fontName, size: size)
        }
        
        // Fallback to system font with appropriate weight
        let systemWeight: Font.Weight = {
            switch weight {
            case .light: return .light
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            }
        }()

        return Font.system(size: size, weight: systemWeight)
    }
    
    /// Returns a custom font with the specified text style and weight, supporting Dynamic Type
    /// - Parameters:
    ///   - style: The text style to use (e.g., .title, .body, .caption)
    ///   - weight: The font weight to use
    /// - Returns: A Font instance with the custom font using relative sizing, or system font as fallback
    func font(style: Font.TextStyle, weight: FontWeight = .regular) -> Font {
        // If no custom font family is configured, use system font directly
        guard shouldUseCustomFonts else {
            let systemWeight: Font.Weight = {
                switch weight {
                case .light: return .light
                case .regular: return .regular
                case .medium: return .medium
                case .semibold: return .semibold
                case .bold: return .bold
                }
            }()
            return Font.system(style, design: .default).weight(systemWeight)
        }
        
        let fontName = "\(customFontFamily)\(weight.rawValue.isEmpty ? "" : "-\(weight.rawValue)")"
        
        // Check if the font is available
        if NSFont(name: fontName, size: baseSizeForStyle(style)) != nil {
            return Font.custom(fontName, size: baseSizeForStyle(style), relativeTo: style)
        }
        
        // Fallback to system font with appropriate weight
        let systemWeight: Font.Weight = {
            switch weight {
            case .light: return .light
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            }
        }()
        
        return Font.system(style, design: .default).weight(systemWeight)
    }
    
    /// Returns the base font size for a given text style
    /// - Parameter style: The text style
    /// - Returns: The base font size for that style
    private func baseSizeForStyle(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 31
        case .title: return 25
        case .title2: return 19
        case .title3: return 17
        case .headline: return 14
        case .body: return 14
        case .callout: return 13
        case .subheadline: return 12
        case .footnote: return 10
        case .caption: return 9
        case .caption2: return 8
        @unknown default: return 14
        }
    }
    
    /// Converts SwiftUI Font.Weight to FontManager.FontWeight
    /// - Parameter weight: SwiftUI Font.Weight
    /// - Returns: Corresponding FontManager.FontWeight
    func fontWeight(from weight: Font.Weight) -> FontWeight {
        switch weight {
        case .ultraLight, .thin, .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold, .heavy, .black: return .bold
        default: return .regular
        }
    }
    
    /// Returns the current custom font family name
    var currentFontFamily: String {
        return customFontFamily
    }
    
    /// Returns whether custom fonts are currently enabled
    var isUsingCustomFonts: Bool {
        return shouldUseCustomFonts
    }
}
