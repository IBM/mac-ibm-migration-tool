//
//  AppPathDiscovery.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 08/05/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import AppKit

/// Service class responsible for discovering application support files across the system
final class AppPathDiscovery: Sendable {
    
    // MARK: - Enums
    
    /// Search sensitivity levels for file matching
    enum SearchSensitivity {
        case strict      // Exact matches only
        case enhanced    // Partial matches, bundle ID components
    }
    
    // MARK: - Constants
    
    /// Search locations limited to 5 key directories
    private struct SearchLocations {
        static let applicationSupportPaths: [String] = {
            let localAppSupportPaths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).map { $0.relativePath }
            let systemAppSupportPaths = FileManager.default.urls(for: .applicationSupportDirectory, in: .systemDomainMask).map { $0.relativePath }
            return systemAppSupportPaths + localAppSupportPaths
        }()
        
        static let containerPath = "\(NSHomeDirectory())/Library/Containers"
        static let groupContainerPath = "\(NSHomeDirectory())/Library/Group Containers"
        static let preferencesPath = "\(NSHomeDirectory())/Library/Preferences"
    }
    
    // swiftlint:disable force_try
    /// Precompiled UUID regex for container matching
    private static let uuidRegex: NSRegularExpression = {
        return try! NSRegularExpression(pattern: "^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$",
                                        options: .caseInsensitive)
    }()
    // swiftlint:enable force_try
    
    // MARK: - Directory Listing Cache

    /// Caches directory listings for the shared system locations scanned per app
    /// (Application Support, Containers, Group Containers, Preferences, and any shared
    /// vendor-wide group container inspected for a nested app-specific subfolder). A single
    /// `AppPathDiscovery` instance is reused across many apps in one discovery session, so
    /// without this cache each of those locations gets listed from disk once per app instead
    /// of once per session. An actor keeps concurrent access from the four scan tasks safe
    /// without manual locking.
    private actor DirectoryListingCache {
        private var cache: [String: [URL]] = [:]

        func contents(at path: String) -> [URL] {
            if let cached = cache[path] {
                return cached
            }
            let contents = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path),
                                                                          includingPropertiesForKeys: nil,
                                                                          options: .skipsHiddenFiles)) ?? []
            cache[path] = contents
            return contents
        }
    }

    // MARK: - Properties

    private let logger = MLogger.main.scoped(to: .discovery)
    private let listingCache = DirectoryListingCache()
    
    // MARK: - Public Methods
    
    /// Discovers all support files for a given application
    /// - Parameters:
    ///   - name: Display name of the discovered application
    ///   - appURL: URL of the application bundle
    ///   - sensitivity: Search sensitivity level (default: enhanced)
    /// - Returns: AppInfo object containing all discovered paths
    func discoverPaths(forAppNamed name: String,
                       at appURL: URL,
                       sensitivity: SearchSensitivity = .enhanced) async -> AppInfo {
        
        // Extract app metadata
        guard let bundle = Bundle(url: appURL) else {
            logger.log("appPathDiscovery.discoveryPaths: Failed to create bundle for \(name)", type: .error)
            return await AppInfo(bundleIdentifier: "",
                                 appName: name,
                                 path: appURL)
        }
        
        let bundleID = bundle.bundleIdentifier ?? ""
        let entitlements = extractEntitlements(from: appURL)
        let teamID = extractTeamIdentifier(from: appURL)
        
        logger.log("appPathDiscovery.discoveryPaths: Starting discovery for \(name) (bundleID: \(bundleID))")
        
        // Perform discovery in parallel; each scan returns its own Sendable result so nothing
        // mutates a shared, non-Sendable object from multiple concurrent tasks.
        async let applicationSupportFiles = scanApplicationSupport(bundleID: bundleID, appName: name, teamID: teamID, sensitivity: sensitivity)
        async let containerFiles = scanContainers(bundleID: bundleID)
        async let groupContainerFiles = scanGroupContainers(bundleID: bundleID,
                                                             appName: name,
                                                             teamID: teamID,
                                                             entitlements: entitlements,
                                                             sensitivity: sensitivity)
        async let preferenceFiles = scanPreferences(bundleID: bundleID, sensitivity: sensitivity)
        
        let appInfo = await AppInfo(bundleIdentifier: bundleID,
                                    appName: name.replacingOccurrences(of: ".app", with: ""),
                                    path: appURL,
                                    entitlements: entitlements,
                                    teamIdentifier: teamID,
                                    applicationSupportFiles: applicationSupportFiles,
                                    containerFiles: containerFiles,
                                    groupContainerFiles: groupContainerFiles,
                                    preferenceFiles: preferenceFiles)
        
        logger.log("appPathDiscovery.discoveryPaths: Completed discovery for \(name) - found \(await appInfo.discoveredFileCount) items")
        
        return appInfo
    }
    
    // MARK: - Private Discovery Methods
    
    /// Scans Application Support directories for app-related files
    private func scanApplicationSupport(bundleID: String, appName: String, teamID: String?, sensitivity: SearchSensitivity) async -> Set<URL> {
        let formattedBundleID = bundleID.normalize()
        let formattedAppName = appName.normalize()
        var found: Set<URL> = []
        
        for location in SearchLocations.applicationSupportPaths {
            let contents = await listingCache.contents(at: location)

            for item in contents {
                let itemName = item.lastPathComponent.normalize()
                
                if matches(itemName: itemName,
                           bundleID: formattedBundleID,
                           appName: formattedAppName,
                           teamID: teamID,
                           sensitivity: sensitivity) {
                    found.insert(item)
                    logger.log("appPathDiscovery.scanApplicationSupport: Found Application Support item: \(item.lastPathComponent)")
                }
            }
        }
        return found
    }
    
    /// Scans Containers directory for UUID-based app containers
    private func scanContainers(bundleID: String) async -> Set<URL> {
        let containersPath = SearchLocations.containerPath
        let containers = await listingCache.contents(at: containersPath)
        var found: Set<URL> = []

        for container in containers {
            let containerName = container.lastPathComponent

            // Check if it's a UUID-based container
            guard Self.uuidRegex.firstMatch(in: containerName,
                                            options: [],
                                            range: NSRange(location: 0, length: containerName.utf16.count)) != nil else {
                continue
            }
            
            // Check metadata plist for bundle ID match
            let metadataPath = container.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
            
            if let metadata = NSDictionary(contentsOf: metadataPath),
               let containerBundleID = metadata["MCMMetadataIdentifier"] as? String,
               containerBundleID == bundleID {
                found.insert(container)
                logger.log("appPathDiscovery.scanContainers: Found Container: \(containerName)")
            }
        }
        return found
    }
    
    /// Scans Group Containers directory for app-related group containers.
    ///
    /// Group containers are frequently shared across an entire vendor's app suite
    /// (e.g. all Microsoft Office apps use a single `<TeamID>.Office` group container).
    /// When a container only matches via team ID or entitlements rather than an exact
    /// bundle ID/app name match, the app-specific data usually lives in a nested
    /// subdirectory (e.g. "UBF8T346G9.Office/Outlook/Outlook 15 Profiles/Main Profile")
    /// rather than at the container root, so those shared containers are also scanned
    /// one level deeper for app-named subdirectories.
    private func scanGroupContainers(bundleID: String, appName: String, teamID: String?, entitlements: [String]?, sensitivity: SearchSensitivity) async -> Set<URL> {
        let groupContainersPath = SearchLocations.groupContainerPath
        let formattedBundleID = bundleID.normalize()
        let formattedAppName = appName.normalize()
        var found: Set<URL> = []

        let containers = await listingCache.contents(at: groupContainersPath)

        for container in containers {
            let containerName = container.lastPathComponent.normalize()
            
            // Match by bundle ID or app name (dedicated, app-specific container)
            let isDedicatedMatch = matches(itemName: containerName,
                                           bundleID: formattedBundleID,
                                           appName: formattedAppName,
                                           teamID: nil,
                                           sensitivity: sensitivity)
            
            if isDedicatedMatch {
                found.insert(container)
                logger.log("appPathDiscovery.scanGroupContainers: Found Group Container: \(container.lastPathComponent)")
                continue
            }
            
            // Match by team ID or entitlements (shared, vendor-wide container)
            var isSharedMatch = matches(itemName: containerName,
                                        bundleID: formattedBundleID,
                                        appName: formattedAppName,
                                        teamID: teamID,
                                        sensitivity: sensitivity)
            
            if !isSharedMatch, let entitlements {
                for entitlement in entitlements {
                    let formattedEntitlement = entitlement.normalize()
                    if containerName.contains(formattedEntitlement) {
                        isSharedMatch = true
                        break
                    }
                }
            }
            
            guard isSharedMatch else { continue }
            let appSpecificSubdirectories = await listingCache.contents(at: container.path)
            if !appSpecificSubdirectories.isEmpty {
                var foundNestedMatch = false
                for subitem in appSpecificSubdirectories {
                    let subitemName = subitem.lastPathComponent.normalize()
                    if matches(itemName: subitemName,
                               bundleID: formattedBundleID,
                               appName: formattedAppName,
                               teamID: nil,
                               sensitivity: sensitivity) {
                        found.insert(subitem)
                        logger.log("appPathDiscovery.scanGroupContainers: Found nested Group Container item: \(subitem.lastPathComponent)")
                        foundNestedMatch = true
                    }
                }
                
                // Fall back to the whole shared container if no app-named subdirectory was found,
                // so data isn't silently dropped when a vendor uses an unexpected nested layout.
                if !foundNestedMatch {
                    found.insert(container)
                    logger.log("appPathDiscovery.scanGroupContainers: Found Group Container: \(container.lastPathComponent)")
                }
            } else {
                found.insert(container)
                logger.log("appPathDiscovery.scanGroupContainers: Found Group Container: \(container.lastPathComponent)")
            }
        }
        return found
    }
    
    /// Scans Preferences directory for app-related .plist files
    private func scanPreferences(bundleID: String, sensitivity: SearchSensitivity) async -> Set<URL> {
        let preferencesPath = SearchLocations.preferencesPath
        let formattedBundleID = bundleID.normalize()
        var found: Set<URL> = []

        let preferences = await listingCache.contents(at: preferencesPath)

        for pref in preferences where pref.pathExtension == "plist" {
            let prefName = pref.deletingPathExtension().lastPathComponent.normalize()
            
            // Match by bundle ID (preferences are typically named after bundle ID)
            if sensitivity == .strict {
                if prefName == formattedBundleID {
                    found.insert(pref)
                    logger.log("appPathDiscovery.scanPreferences: Found Preference: \(pref.lastPathComponent)")
                }
            } else {
                if prefName.contains(formattedBundleID) {
                    found.insert(pref)
                    logger.log("appPathDiscovery.scanPreferences: Found Preference: \(pref.lastPathComponent)")
                }
            }
        }
        return found
    }
    
    // MARK: - Helper Methods
    
    /// Determines if an item name matches the app based on sensitivity level
    private func matches(itemName: String,
                         bundleID: String,
                         appName: String,
                         teamID: String?,
                         sensitivity: SearchSensitivity) -> Bool {
        let formattedTeamID = teamID?.normalize()
        
        switch sensitivity {
        case .strict:
            return itemName == bundleID || itemName == appName || (formattedTeamID != nil ? (itemName == formattedTeamID!.appending(".\(appName)") || itemName == formattedTeamID!.appending(".\(bundleID)")) : false)
        case .enhanced:
            return itemName.contains(bundleID) || itemName.contains(appName) || (formattedTeamID != nil ? itemName.contains(formattedTeamID!) : false)
        }
    }
    
    /// Extracts entitlements from an app bundle
    private func extractEntitlements(from appURL: URL) -> [String]? {
        // Try to read entitlements from the app's code signature
        let executablePath = appURL.appendingPathComponent("Contents/MacOS")
        
        guard let executableName = try? FileManager.default.contentsOfDirectory(atPath: executablePath.path).first else {
            return nil
        }
        
        let fullExecutablePath = executablePath.appendingPathComponent(executableName)
        
        // Use codesign to extract entitlements
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-d", "--entitlements", ":-", fullExecutablePath.path]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            
            if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                // Extract relevant entitlement keys
                var entitlements: [String] = []
                
                for (key, _) in plist {
                    entitlements.append(key)
                }
                
                return entitlements.isEmpty ? nil : entitlements
            }
        } catch {
            logger.log("appPathDiscovery.extractEntitlements: Failed to extract entitlements: \(error)")
        }
        
        return nil
    }
    
    /// Extracts team identifier from an app bundle
    private func extractTeamIdentifier(from appURL: URL) -> String? {
        let executablePath = appURL.appendingPathComponent("Contents/MacOS")
        
        guard let executableName = try? FileManager.default.contentsOfDirectory(atPath: executablePath.path).first else {
            return nil
        }
        
        let fullExecutablePath = executablePath.appendingPathComponent(executableName)
        
        // Use codesign to extract team identifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-dvv", fullExecutablePath.path]
        
        let pipe = Pipe()
        task.standardError = pipe  // codesign outputs to stderr
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Look for TeamIdentifier line
                if let range = output.range(of: "TeamIdentifier=") {
                    let teamIDStart = output.index(range.upperBound, offsetBy: 0)
                    if let lineEnd = output[teamIDStart...].firstIndex(of: "\n") {
                        return String(output[teamIDStart..<lineEnd])
                    }
                }
            }
        } catch {
            logger.log("appPathDiscovery.extractTeamIdentifier: Failed to extract team identifier: \(error)")
        }
        
        return nil
    }
}
