//
//  Utils.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 14/11/2023.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//
// swiftlint:disable file_length nesting

import os.log
import Foundation
import AppKit

/// Utility functions for logging messages, retrieving interface styles, free space on the device,
/// and getting the user's folder name.
struct Utils {
    struct Common {
        /// Retrieves the free space on the device.
        static var freeSpaceOnDevice: Int {
            let fileURL = FileManager.default.homeDirectoryForCurrentUser
            do {
                let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                if let capacity = values.volumeAvailableCapacityForImportantUsage {
                    let freeSpace = Int(capacity)
                    return freeSpace
                } else {
                    return 0
                }
            } catch {
                return 0
            }
        }
        
        /// The correct page to use for runnin Jamf Inventory Update based on the desired method.
        static var reconPage: MigratorPage {
            switch AppContext.jamfReconMethod {
            case .direct:
                return .recon
            case .selfServicePolicy:
                return .final
            }
        }
        
        /// A localized label for the System Settings app name that adapts to the current macOS version.
        static var systemSettingsLabel: String {
            if #available(macOS 13.0, *) {
                return "common.system.settings.ventura.label".localized
            } else {
                return "common.system.settings.pre.ventura.label".localized
            }
        }
        
        /// Generate a random code.
        /// - Parameter digits: number of digits of the code.
        /// - Returns: string with the generated code.
        static func generateRandomCode(digits: Int) -> String {
            var number = String()
            for _ in 1...digits {
                number += "\(Int.random(in: 1...9))"
            }
            return number
        }
        
        /// Prevents the display from sleeping.
        static func preventSleep() {
            MLogger.main.log("utils.preventSleep: Preventing Mac to enter sleep.", type: .default)
            var assertionID: IOPMAssertionID = IOPMAssertionID(0)
            _ = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Prevent display sleep during critical operations" as CFString, &assertionID) == kIOReturnSuccess
            
        }
        
        /// Restart the device using an Apple Script to communicate with "System Events"
        static func rebootMac() {
            MLogger.main.log("utils.rebootMac: Restarting Mac.", type: .default)
            var errors: NSDictionary?
            _ = NSAppleScript(source: "tell app \"System Events\" to restart")?.executeAndReturnError(&errors)
        }
    }
}

extension Utils {
    struct Window {
        /// Set the window level for the app to "floating" or "normal" based on the flag.
        /// - Parameter floating: if true the window level is set to "floating", if false the window leve is set to "normal"
        static func makeWindowFloating(_ floating: Bool = true) {
            MLogger.main.log("utils.makeWindowFloating: Setting app windows level to \(floating ? "floating" : "normal").", type: .default)
            for window in NSApplication.shared.windows {
                window.level = floating ? .floating : .normal
            }
        }
        
        /// Remove the `Close` UI button from the app Toolbar.
        static func removeClosableToolbarElement() {
            for window in NSApplication.shared.windows {
                window.styleMask.subtract(.closable)
            }
        }
        
        /// Restore the `Close` UI button in the app Toolbar.
        static func restoreClosableToolbarElement() {
            for window in NSApplication.shared.windows {
                window.styleMask.update(with: .closable)
            }
        }
    }
}

extension Utils {
    struct LaunchAgentHelpers {
        
        /// Install a Launch Agent on the device to restart the app once the planned reboot happen.
        static func installLaunchAgent() async {
            MLogger.main.log("utils.installLaunchAgent: Creating Launch Agent plist.", type: .default)
            let fileContent = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>mac.ibm.shift</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/\(Bundle.main.name).app/Contents/MacOS/\(Bundle.main.name)</string>
    </array>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
"""
            FileManager.default.createFile(atPath: FileManager.default.homeDirectoryForCurrentUser.relativePath + "/Library/LaunchAgents/com.ibm.cio.be.migrator.plist", contents: fileContent.data(using: .utf8)!)
            MLogger.main.log("utils.installLaunchAgent: Loading Launch Agent.", type: .default)
            await withCheckedContinuation { continuation in
                _ = NSAppleScript(source: "do shell script \"launchctl bootstrap gui/501 \(FileManager.default.homeDirectoryForCurrentUser.relativePath + "/Library/LaunchAgents/com.ibm.cio.be.migrator.plist") \"")?.executeAndReturnError(nil)
                continuation.resume()
            }
            MLogger.main.log("utils.installLaunchAgent: Launch Agent installed.", type: .default)
        }
        
        /// Remove the Launch Agent from the device.
        static func removeLaunchAgent() async {
            MLogger.main.log("utils.removeLaunchAgent: Unloading Launch Agent.", type: .default)
            await withCheckedContinuation { continuation in
                _ = NSAppleScript(source: "do shell script \"launchctl bootout gui/501 \(FileManager.default.homeDirectoryForCurrentUser.relativePath + "/Library/LaunchAgents/com.ibm.cio.be.migrator.plist") \"")?.executeAndReturnError(nil)
                continuation.resume()
            }
            MLogger.main.log("utils.removeLaunchAgent: Removing Launch Agent plist.", type: .default)
            do {
                try FileManager.default.removeItem(atPath: FileManager.default.homeDirectoryForCurrentUser.relativePath + "/Library/LaunchAgents/com.ibm.cio.be.migrator.plist")
                MLogger.main.log("utils.removeLaunchAgent: Launch Agent removed.", type: .default)
            } catch {
                MLogger.main.log("utils.removeLaunchAgent: Error encountered while removing Launch Agent plist. Error: \(error.localizedDescription).", type: .default)
            }
        }
    }
}

extension Utils {
    struct Customization {
        fileprivate static let regexDelimeter = "#"
        
        /// Checks if a string contains regex special characters that require pattern matching.
        /// Dots are intentionally excluded because they commonly appear in file names.
        /// - Parameter str: The string to check for regex patterns.
        /// - Returns: True if the string contains regex special characters, false otherwise.
        fileprivate static func containsRegexPattern(_ str: String) -> Bool {
            let regexChars = CharacterSet(charactersIn: "\\+*?[]{}()^$|")
            return str.rangeOfCharacter(from: regexChars) != nil
        }
        
        /// Wraps regex path components in delimiters while keeping plain components literal.
        /// - Parameter path: The path suffix to normalize.
        /// - Returns: Normalized path components ready to be appended to a base URL.
        private static func normalizedPathComponents(from path: String) -> [String] {
            path
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
                .map { component in
                    guard containsRegexPattern(component) else { return component }
                    return "\(regexDelimeter)\(component)\(regexDelimeter)"
                }
        }
        
        /// Appends normalized path components to a base URL.
        /// - Parameters:
        ///   - components: The path components to append.
        ///   - baseURL: The base URL to append them to.
        /// - Returns: The resulting URL.
        private static func appendingPathComponents(_ components: [String], to baseURL: URL) -> URL {
            components.reduce(baseURL) { partialURL, component in
                partialURL.appendingPathComponent(component)
            }
        }
        
        /// Parses a profile URL string that may contain special placeholders like $HOMEFOLDER or $APPFOLDER
        /// and converts it to an actual URL. Regex support is limited to isolated path components so plain
        /// file names such as `Safari.app` continue to be treated as literals.
        /// - Parameter urlString: The URL string to parse, which may contain placeholders.
        /// - Returns: A URL object representing the parsed path, or nil if parsing fails.
        static func parseProfileURL(_ urlString: String) -> URL? {
            if urlString.contains("$HOMEFOLDER") {
                let finalUrl = urlString.replacingOccurrences(of: "$HOMEFOLDER", with: "")
                let pathComponents = normalizedPathComponents(from: finalUrl)
                return appendingPathComponents(pathComponents, to: FileManager.default.homeDirectoryForCurrentUser)
            }
            if urlString.contains("$APPFOLDER") {
                let finalUrl = urlString.replacingOccurrences(of: "$APPFOLDER", with: "")
                let pathComponents = normalizedPathComponents(from: finalUrl)
                guard let applicationsURL = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first else {
                    return nil
                }
                return appendingPathComponents(pathComponents, to: applicationsURL)
            }
            
            let pathComponents = normalizedPathComponents(from: urlString)
            if urlString.starts(with: "/") {
                return appendingPathComponents(pathComponents, to: URL(fileURLWithPath: "/"))
            }
            return appendingPathComponents(pathComponents, to: FileManager.default.homeDirectoryForCurrentUser)
        }
    }
}

extension Utils {
    /// Represents the hierarchical relationship between two file system URLs.
    ///
    /// Cases:
    /// - `same`: Both URLs refer to the exact same file system location after standardization.
    /// - `contains`: The first URL represents a directory that is an ancestor of the second URL
    ///   (i.e., the first path contains the second path).
    /// - `containedBy`: The first URL is a descendant of the second URL
    ///   (i.e., the first path is contained by the second path).
    /// - `notRelated`: The two URLs do not share a common ancestor beyond their divergent components,
    ///   meaning neither contains the other and they are not the same path.
    enum FileRelationship {
        case same
        case contains
        case containedBy
        case notRelated
    }
    struct FileManagerHelpers {
        /// Retrieves the user's folder name.
        static var userFolderName: String {
            return FileManager.default.homeDirectoryForCurrentUser.lastPathComponent
        }
        
        /// Retrieves the status of iCloud on the device.
        static var iCloudAvailable: Bool {
            return FileManager.default.ubiquityIdentityToken != nil
        }
        
        /// Determines the hierarchical relationship between two file system URLs.
        ///
        /// This method compares the standardized file URLs of two paths to establish whether:
        /// - they point to the exact same location,
        /// - one path is an ancestor directory that contains the other,
        /// - one path is a descendant contained by the other,
        /// - or they are unrelated (diverge at some path component).
        ///
        /// - Parameters:
        ///   - firstURL: The URL representing the first file or directory to compare.
        ///   - secondURL: The URL representing the second file or directory to compare.
        /// - Returns: A `FileRelationship` value describing how the two URLs relate:
        ///   - `.same` if both URLs resolve to the same standardized location,
        ///   - `.contains` if `firstURL` is an ancestor directory of `secondURL`,
        ///   - `.containedBy` if `firstURL` is a descendant of `secondURL`,
        ///   - `.notRelated` if neither contains the other and they diverge at some component.
        static func getRelationship(ofItemAt firstURL: URL, toItemAt secondURL: URL) -> FileRelationship {
            let firstStandardized = firstURL.standardizedFileURL
            let secondStandardized = secondURL.standardizedFileURL
            
            if firstStandardized == secondStandardized {
                return .same
            }
            
            let firstComponents = firstStandardized.pathComponents
            let secondComponents = secondStandardized.pathComponents
            
            if components(firstComponents, matchPatternComponents: secondComponents) {
                return .same
            }
            if firstComponents.count > secondComponents.count &&
                components(Array(firstComponents.prefix(secondComponents.count)), matchPatternComponents: secondComponents) {
                return .contains
            }
            if firstComponents.count < secondComponents.count &&
                components(firstComponents, matchPatternComponents: Array(secondComponents.prefix(firstComponents.count))) {
                return .containedBy
            }
            
            return .notRelated
        }
        
        // swiftlint:disable function_body_length
        /// Checks if a file or directory is synced with a cloud service like iCloud Drive, OneDrive, Box, etc.
        /// - Parameter pathURL: The URL to check for cloud sync status.
        /// - Returns: True if the file is synced with a cloud service, false otherwise.
        static func isCloudSyncedPath(_ pathURL: URL) -> Bool {
            let path = pathURL.path
            // Check for iCloud Drive
            if path.contains("/Library/Mobile Documents/com~apple~CloudDocs/") {
                MLogger.main.log("utils.isCloudSyncedPath: iCloud Drive file detected: \(path)", type: .debug)
                return true
            }
            // Check for iCloud Drive app-specific containers
            if path.contains("/Library/Mobile Documents/") && !path.contains("/Library/Mobile Documents/com~apple~CloudDocs/") {
                let components = path.components(separatedBy: "/")
                if let index = components.firstIndex(of: "Mobile Documents"),
                   index + 1 < components.count,
                   components[index + 1].contains("~") {
                    MLogger.main.log("utils.isCloudSyncedPath: iCloud app container detected: \(path)", type: .debug)
                    return true
                }
            }
            // Check for OneDrive
            if path.contains("/OneDrive") || path.contains("/OneDrive - ") {
                MLogger.main.log("utils.isCloudSyncedPath: OneDrive file detected: \(path)", type: .debug)
                return true
            }
            // Check for Box
            if path.contains("/Box/") || path.contains("/Box Sync/") {
                MLogger.main.log("utils.isCloudSyncedPath: Box file detected: \(path)", type: .debug)
                return true
            }
            // Check for Dropbox
            if path.contains("/Dropbox/") {
                MLogger.main.log("utils.isCloudSyncedPath: Dropbox file detected: \(path)", type: .debug)
                return true
            }
            // Check for Google Drive
            if path.contains("/Google Drive/") || path.contains("/Google Drive File Stream/") || path.contains("/Google/DriveFS/") {
                MLogger.main.log("utils.isCloudSyncedPath: Google Drive file detected: \(path)", type: .debug)
                return true
            }
            // Check for pCloud
            if path.contains("/pCloud Drive/") {
                MLogger.main.log("utils.isCloudSyncedPath: pCloud file detected: \(path)", type: .debug)
                return true
            }
            // Check for Sync.com
            if path.contains("/Sync/") {
                MLogger.main.log("utils.isCloudSyncedPath: Sync.com file detected: \(path)", type: .debug)
                return true
            }
            // Check for MEGA
            if path.contains("/MEGA/") {
                MLogger.main.log("utils.isCloudSyncedPath: MEGA file detected: \(path)", type: .debug)
                return true
            }
            // Check for iCloud Drive symlinks in user directory
            if path.contains("/iCloud Drive") || path.contains("/iCloud/") {
                MLogger.main.log("utils.isCloudSyncedPath: iCloud Drive symlink detected: \(path)", type: .debug)
                return true
            }
            // Check for extended attributes that might indicate cloud sync
            if let resourceValues = try? pathURL.resourceValues(forKeys: [.isUbiquitousItemKey]),
               let isUbiquitousItem = resourceValues.isUbiquitousItem, isUbiquitousItem {
                MLogger.main.log("utils.isCloudSyncedPath: iCloud ubiquitous item detected: \(path)", type: .debug)
                return true
            }
            return false
        }
        // swiftlint:enable function_body_length
        
        /// Determines whether a given path should be ignored during file operations.
        /// - Parameter pathURL: The URL to check against exclusion rules.
        /// - Returns: True if the path should be ignored, false otherwise.
        static func shouldIgnorePath(_ pathURL: URL) -> Bool {
            if isCloudSyncedPath(pathURL) {
                return true
            }
            
            let ext = pathURL.pathExtension
            if !ext.isEmpty && AppContext.excludedFileExtensions.contains(ext) {
                return true
            }
            
            let fileName = pathURL.lastPathComponent
            if AppContext.excludedFilePrefixes.contains(where: { fileName.hasPrefix($0) || fileName == $0 }) {
                return true
            }
            
            let exclusionList = AppContext.urlExclusionList.compactMap { $0 }
            
            var shouldIgnore = false
            for excludedURL in exclusionList {
                let relationship = getRelationship(ofItemAt: pathURL, toItemAt: excludedURL)
                if relationship == .same || relationship == .contains {
                    shouldIgnore = true
                    break
                }
            }
            if shouldIgnore {
                let allowList = AppContext.explicitAllowList.compactMap { $0 }
                for allowedURL in allowList {
                    let relationship = getRelationship(ofItemAt: pathURL, toItemAt: allowedURL)
                    if relationship == .same || relationship == .contains || relationship == .containedBy {
                        return false
                    }
                }
            }
            return shouldIgnore
        }
        
        /// Returns true if `url` matches `patternURL`, where components in `patternURL`
        /// are treated as regular expressions using `NSRegularExpression`.
        static func url(_ url: URL, matchesPatternURL patternURL: URL) -> Bool {
            let lhs = url.standardizedFileURL
            let rhs = patternURL.standardizedFileURL
            return components(lhs.pathComponents, matchPatternComponents: rhs.pathComponents)
        }
        
        /// Returns an `NSRegularExpression` if the component is meant to be treated as a regex.
        private static func nsRegexFromPatternComponent(_ component: String) -> NSRegularExpression? {
            let normalizedComponent: String
            
            if component.hasPrefix(Utils.Customization.regexDelimeter),
               component.hasSuffix(Utils.Customization.regexDelimeter),
               component.count > 2 {
                normalizedComponent = String(component.dropFirst().dropLast())
            } else if Utils.Customization.containsRegexPattern(component) {
                normalizedComponent = component
            } else {
                return nil
            }
            
            return try? NSRegularExpression(pattern: "^(?:\(normalizedComponent))$")
        }
        
        /// Matches URL path components against pattern components, allowing regex in the pattern side.
        private static func components(_ pathComponents: [String], matchPatternComponents patternComponents: [String]) -> Bool {
            guard pathComponents.count == patternComponents.count else { return false }
            
            for (pathComponent, patternComponent) in zip(pathComponents, patternComponents) {
                if patternComponent == "/" || pathComponent == "/" {
                    guard patternComponent == pathComponent else { return false }
                    continue
                }
                
                if let regex = nsRegexFromPatternComponent(patternComponent) {
                    let range = NSRange(pathComponent.startIndex..<pathComponent.endIndex, in: pathComponent)
                    guard regex.firstMatch(in: pathComponent, options: [], range: range) != nil else {
                        return false
                    }
                    continue
                }
                
                guard pathComponent == patternComponent else { return false }
            }
            
            return true
        }
    }
}

extension Utils {
    struct UserDefaultsHelpers {
        /// A collection of UserDefaults keys used to persist migration report metadata.
        enum ReportKeys: String, CaseIterable {
            case lastMigrationStartDate
            case lastMigrationEndDate
            case lastMigrationTargetDevice
            case lastMigrationErrors
            case lastMigrationSize
            case lastMigrationTransferMethod
            case lastMigrationChosenOption
        }
        
        /// The array of keys defined in the UserDefaults domain.
        private static let customizedKeys: Dictionary<String, Any>.Keys = UserDefaults.standard.dictionaryRepresentation().keys
        
        /// Removes any previously stored values from UserDefaults for all custom configuration keys,
        /// except for the Terms & Conditions acceptance key.
        static func cleanUpCustomKeys() {
            for key in customizedKeys where (key != AppContext.tAndCUserAcceptanceKey
                                             && key != AppContext.loggingLevelUserDefaultsKey
                                             && !ReportKeys.allCases.contains(where: { $0.rawValue == key })) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        
        /// Determines whether a value for the specified UserDefaults key is acceptable to use.
        ///
        /// In debug builds, this method always returns true to allow developers to test with locally set values
        /// without requiring device management profiles. In release builds, it only returns true if the value
        /// for the given key is managed (i.e., enforced) via configuration profiles or MDM.
        ///
        /// - Parameter key: The UserDefaults key to evaluate for acceptability.
        /// - Returns: A Boolean value indicating whether the value for the given key should be considered valid:
        ///   - true if running a debug build, or if in a release build the key is enforced by management,
        ///   - false otherwise.
        static func isDefaultsValueAcceptable(forKey key: String) -> Bool {
#if DEBUG
            return true
#else
            return UserDefaults.standard.objectIsForced(forKey: key)
#endif
        }
        
        /// Retrieves a managed value from UserDefaults for the specified key, falling back to a default when appropriate.
        ///
        /// This method returns a value for the given key only when:
        /// - The key exists in the current UserDefaults domain (i.e., it is known/defined), and
        /// - The value is acceptable to use according to management rules:
        ///   - In debug builds, any locally set value is accepted (useful for development and testing).
        ///   - In release builds, only values enforced by management (e.g., via MDM or configuration profiles) are accepted.
        ///
        /// - Parameters:
        ///   - key: The UserDefaults key whose value should be retrieved.
        ///   - defaultValue: The value to return if the key is not acceptable or the stored value is missing or of a different type.
        /// - Returns: The managed value for `key` cast to type `T` when acceptable and available; otherwise `defaultValue`.
        static func managedValue<T>(forKey key: String, defaultValue: T) -> T {
            guard customizedKeys.contains(key) && Self.isDefaultsValueAcceptable(forKey: key) else {
                return defaultValue
            }
            return UserDefaults.standard.value(forKey: key) as? T ?? defaultValue
        }
    }
}

// swiftlint:enable file_length nesting
