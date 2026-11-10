//
//  AppInfo.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 08/05/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import AppKit

/// Model class that stores comprehensive application metadata and discovered support file paths
@MainActor
final class AppInfo {
    
    // MARK: - Properties
    
    /// Bundle identifier of the application
    let bundleIdentifier: String
    
    /// Display name of the application
    let appName: String
    
    /// Path to the application bundle
    let path: URL
    
    /// Application entitlements (optional)
    let entitlements: [String]?
    
    /// Team identifier from code signing (optional)
    let teamIdentifier: String?
    
    // MARK: - Discovered Paths by Category
    
    /// Files discovered in Application Support directories
    var applicationSupportFiles: Set<URL> = []
    
    /// Files discovered in Containers directory
    var containerFiles: Set<URL> = []
    
    /// Files discovered in Group Containers directory
    var groupContainerFiles: Set<URL> = []
    
    /// Preference files (.plist) discovered
    var preferenceFiles: Set<URL> = []
    
    // MARK: - Computed Properties
    
    /// All discovered paths combined
    var allDiscoveredPaths: Set<URL> {
        return applicationSupportFiles
            .union(containerFiles)
            .union(groupContainerFiles)
            .union(preferenceFiles)
    }
    
    /// Count of all discovered support files
    var discoveredFileCount: Int {
        return allDiscoveredPaths.count
    }
    
    // MARK: - Internal Properties
    
    /// Cached total size to avoid recalculation (internal for DiscoveredApplication access)
    var cachedTotalSize: Int?
    
    /// Cached support file count to avoid recalculation.
    var cachedTotalFileCount: Int?
    
    // MARK: - Initializer
    
    /// Initialize AppInfo with application metadata
    /// - Parameters:
    ///   - bundleIdentifier: Bundle identifier of the app
    ///   - appName: Display name of the app
    ///   - path: Path to the app bundle
    ///   - entitlements: Optional array of entitlements
    ///   - teamIdentifier: Optional team identifier
    init(bundleIdentifier: String,
         appName: String,
         path: URL,
         entitlements: [String]? = nil,
         teamIdentifier: String? = nil,
         applicationSupportFiles: Set<URL> = [],
         containerFiles: Set<URL> = [],
         groupContainerFiles: Set<URL> = [],
         preferenceFiles: Set<URL> = []) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.path = path
        self.entitlements = entitlements
        self.teamIdentifier = teamIdentifier
        self.applicationSupportFiles = applicationSupportFiles
        self.containerFiles = containerFiles
        self.groupContainerFiles = groupContainerFiles
        self.preferenceFiles = preferenceFiles
    }
    
    // MARK: - Public Methods
    
    /// Calculates and returns the total size of all discovered support files
    /// Uses FileSizeCache to avoid redundant calculations
    /// - Returns: Total size in bytes
    func getTotalSize() async -> Int {
        // Return cached value if available
        if let cached = cachedTotalSize {
            return cached
        }
        
        var total = 0
        
        for path in allDiscoveredPaths {
            // Check cache first
            if let cached = FileSizeCache.shared.getCachedSize(for: path) {
                total += cached.size
            } else {
                // Calculate size if not cached
                let size = await calculateSize(for: path)
                let fileCount = await calculateFileCount(for: path)
                FileSizeCache.shared.setCachedSize(for: path, size: size, numberOfFiles: fileCount)
                total += size
            }
        }
        
        cachedTotalSize = total
        return total
    }
    
    /// Calculates and returns the total number of files in all discovered paths
    /// Uses FileSizeCache to avoid redundant calculations
    /// - Returns: Total number of files
    func getTotalFileCount() async -> Int {
        // Return cached value if available
        if let cached = cachedTotalFileCount {
            return cached
        }
        
        var total = 0
        
        for path in allDiscoveredPaths {
            // Check cache first
            if let cached = FileSizeCache.shared.getCachedSize(for: path) {
                total += cached.numberOfFiles
            } else {
                // Calculate if not cached
                let size = await calculateSize(for: path)
                let fileCount = await calculateFileCount(for: path)
                FileSizeCache.shared.setCachedSize(for: path, size: size, numberOfFiles: fileCount)
                total += fileCount
            }
        }
        
        cachedTotalFileCount = total
        return total
    }
    
    /// Invalidates cached size and file count
    func invalidateCache() {
        cachedTotalSize = nil
        cachedTotalFileCount = nil
    }
    
    /// Returns a breakdown of sizes by category
    /// - Returns: Dictionary with category names and their sizes
    func getSizeBreakdown() async -> [String: Int] {
        var breakdown: [String: Int] = [:]
        
        breakdown["Application Support"] = await calculateTotalSize(for: applicationSupportFiles)
        breakdown["Containers"] = await calculateTotalSize(for: containerFiles)
        breakdown["Group Containers"] = await calculateTotalSize(for: groupContainerFiles)
        breakdown["Preferences"] = await calculateTotalSize(for: preferenceFiles)
        
        return breakdown
    }
    
    // MARK: - Private Methods
    
    /// Calculates the size of a file or directory
    /// - Parameter url: URL to calculate size for
    /// - Returns: Size in bytes
    private nonisolated func calculateSize(for url: URL) async -> Int {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let size = Utils.FileManagerHelpers.calculateDirectorySize(url)
                continuation.resume(returning: size)
            }
        }
    }
    
    /// Calculates the number of files in a directory (or 1 for a single file)
    /// - Parameter url: URL to count files for
    /// - Returns: Number of files
    private nonisolated func calculateFileCount(for url: URL) async -> Int {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                    continuation.resume(returning: 0)
                    return
                }
                
                if !isDirectory.boolValue {
                    continuation.resume(returning: 1)
                    return
                }
                
                // Count files in directory
                let count = Utils.FileManagerHelpers.countFilesInDirectory(url)
                continuation.resume(returning: count)
            }
        }
    }
    
    /// Calculates total size for a set of URLs
    /// - Parameter urls: Set of URLs to calculate
    /// - Returns: Total size in bytes
    private func calculateTotalSize(for urls: Set<URL>) async -> Int {
        var total = 0
        for url in urls {
            if let cached = FileSizeCache.shared.getCachedSize(for: url) {
                total += cached.size
            } else {
                total += await calculateSize(for: url)
            }
        }
        return total
    }
}

extension AppInfo {
    /// Debug description. Not `CustomStringConvertible`, because that protocol requires a
    /// `nonisolated` property and `discoveredFileCount` depends on main-actor-isolated state.
    var debugSummary: String {
        return """
        AppInfo(name: \(appName),
                bundleID: \(bundleIdentifier),
                discovered: \(discoveredFileCount) files)
        """
    }
}
