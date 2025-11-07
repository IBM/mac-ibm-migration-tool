//
//  CustomizableIconView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 04/11/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI

/// A view that displays a customizable icon that can be loaded from various sources:
/// - Asset catalog (default)
/// - Local file path
/// - Remote URL
/// - Base64 encoded image
struct CustomizableIconView: View {
    
    // MARK: - Properties
    
    /// The page identifier used to fetch the custom icon from UserDefaults
    let pageIdentifier: String
    /// The default asset name to use if no custom icon is configured
    let defaultAssetName: String
    /// The width of the icon
    let width: CGFloat
    /// The height of the icon
    let height: CGFloat
    
    // MARK: - State
    
    @State private var customImage: NSImage?
    @State private var isLoading: Bool = false
    
    // MARK: - Initializer
    
    /// Initialize a customizable icon view
    /// - Parameters:
    ///   - pageIdentifier: The page identifier for fetching custom icon settings
    ///   - defaultAssetName: The default asset name (default: "icon")
    ///   - width: The width of the icon (default: 86)
    ///   - height: The height of the icon (default: 86)
    init(pageIdentifier: String, defaultAssetName: String = "icon", width: CGFloat = 86, height: CGFloat = 86) {
        self.pageIdentifier = pageIdentifier
        self.defaultAssetName = defaultAssetName
        self.width = width
        self.height = height
    }
    
    // MARK: - Body
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(width: width, height: height)
            } else if let customImage = customImage {
                Image(nsImage: customImage)
                    .resizable()
            } else {
                Image(defaultAssetName)
                    .resizable()
            }
        }
        .frame(width: width, height: height)
        .task {
            await loadCustomIcon()
        }
    }
    
    // MARK: - Private Methods
    
    /// Load the custom icon based on the configured source
    private func loadCustomIcon() async {
        guard let iconSource = AppContext.customIconSource(for: pageIdentifier),
              !iconSource.isEmpty else {
            return
        }
        
        await MainActor.run {
            isLoading = true
        }
        
        let image = await loadImage(from: iconSource)
        
        await MainActor.run {
            self.customImage = image
            self.isLoading = false
        }
    }
    
    /// Load an image from various sources
    /// - Parameter source: The source string (file path, URL, or base64)
    /// - Returns: The loaded NSImage, or nil if loading failed
    private func loadImage(from source: String) async -> NSImage? {
        // Check if it's a base64 encoded image
        if source.hasPrefix("data:image/") || source.hasPrefix("base64:") {
            return loadBase64Image(from: source)
        }
        
        // Check if it's a remote URL
        if source.hasPrefix("http://") || source.hasPrefix("https://") {
            return await loadRemoteImage(from: source)
        }
        
        // Treat as local file path
        return loadLocalImage(from: source)
    }
    
    /// Load an image from a base64 encoded string
    /// - Parameter source: The base64 encoded string
    /// - Returns: The decoded NSImage, or nil if decoding failed
    private func loadBase64Image(from source: String) -> NSImage? {
        var base64String = source
        
        // Remove data URI prefix if present
        if source.hasPrefix("data:image/") {
            if let range = source.range(of: "base64,") {
                base64String = String(source[range.upperBound...])
            }
        } else if source.hasPrefix("base64:") {
            base64String = String(source.dropFirst(7))
        }
        
        guard let imageData = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters) else {
            MLogger.main.log("CustomizableIconView: Failed to decode base64 image for page '\(pageIdentifier)'", type: .error)
            return nil
        }
        
        guard let image = NSImage(data: imageData) else {
            MLogger.main.log("CustomizableIconView: Failed to create image from base64 data for page '\(pageIdentifier)'", type: .error)
            return nil
        }
        
        MLogger.main.log("CustomizableIconView: Successfully loaded base64 image for page '\(pageIdentifier)'", type: .default)
        return image
    }
    
    /// Load an image from a remote URL
    /// - Parameter source: The URL string
    /// - Returns: The downloaded NSImage, or nil if download failed
    private func loadRemoteImage(from source: String) async -> NSImage? {
        guard let url = URL(string: source) else {
            MLogger.main.log("CustomizableIconView: Invalid URL '\(source)' for page '\(pageIdentifier)'", type: .error)
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                MLogger.main.log("CustomizableIconView: Failed to download image from '\(source)' for page '\(pageIdentifier)'", type: .error)
                return nil
            }
            
            guard let image = NSImage(data: data) else {
                MLogger.main.log("CustomizableIconView: Failed to create image from downloaded data for page '\(pageIdentifier)'", type: .error)
                return nil
            }
            
            MLogger.main.log("CustomizableIconView: Successfully loaded remote image from '\(source)' for page '\(pageIdentifier)'", type: .default)
            return image
        } catch {
            MLogger.main.log("CustomizableIconView: Error downloading image from '\(source)' for page '\(pageIdentifier)': \(error.localizedDescription)", type: .error)
            return nil
        }
    }
    
    /// Load an image from a local file path
    /// - Parameter source: The file path
    /// - Returns: The loaded NSImage, or nil if loading failed
    private func loadLocalImage(from source: String) -> NSImage? {
        // Expand tilde in path
        let expandedPath = (source as NSString).expandingTildeInPath
        
        // Try to load the image
        guard let image = NSImage(contentsOfFile: expandedPath) else {
            MLogger.main.log("CustomizableIconView: Failed to load image from local path '\(expandedPath)' for page '\(pageIdentifier)'", type: .error)
            return nil
        }
        
        MLogger.main.log("CustomizableIconView: Successfully loaded local image from '\(expandedPath)' for page '\(pageIdentifier)'", type: .default)
        return image
    }
}

#Preview {
    VStack(spacing: 20) {
        CustomizableIconView(pageIdentifier: "welcome")
        CustomizableIconView(pageIdentifier: "browser")
        CustomizableIconView(pageIdentifier: "setup")
    }
    .frame(width: 400, height: 400)
}
