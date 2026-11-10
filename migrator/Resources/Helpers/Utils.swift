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
                number += "\(Int.random(in: 0...9))"
            }
            return number
        }
        
        /// Logger instance.
        private static let logger = MLogger.main.scoped(to: .migration)

        /// Prevents the display from sleeping.
        static func preventSleep() {
            logger.log("utils.preventSleep: preventing Mac from entering sleep", type: .default)
            var assertionID: IOPMAssertionID = IOPMAssertionID(0)
            let succeeded = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Prevent display sleep during critical operations" as CFString, &assertionID) == kIOReturnSuccess
            if !succeeded {
                logger.log("utils.preventSleep: failed to create the power assertion preventing sleep", type: .error)
            }
        }

        /// Restart the device using an Apple Script to communicate with "System Events"
        static func rebootMac() {
            logger.log("utils.rebootMac: restarting Mac", type: .default)
            var errors: NSDictionary?
            _ = NSAppleScript(source: "tell app \"System Events\" to restart")?.executeAndReturnError(&errors)
            if let errors {
                logger.log("utils.rebootMac: reboot AppleScript returned an error -> \"\(errors)\"", type: .error)
            }
        }
    }
}

extension Utils {
    @MainActor
    struct Window {
        /// Set the window level for the app to "floating" or "normal" based on the flag.
        /// - Parameter floating: if true the window level is set to "floating", if false the window leve is set to "normal"
        static func makeWindowFloating(_ floating: Bool = true) {
            MLogger.main.log("utils.makeWindowFloating: setting app window level to \"\(floating ? "floating" : "normal")\"", type: .default, category: .general)
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

        /// Logger instance.
        private static let logger = MLogger.main.scoped(to: .migration)

        /// Location of the Launch Agent plist in the current user's `~/Library/LaunchAgents`.
        private static var launchAgentURL: URL {
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/com.ibm.cio.be.migrator.plist")
        }

        /// Install a Launch Agent on the device to restart the app once the planned reboot happen.
        /// The agent goes through `/usr/bin/open` rather than executing the binary directly: a
        /// process spawned straight by launchd isn't registered with Launch Services as a regular
        /// app launch, so it shows in the Dock but never gets activated or shows its window.
        static func installLaunchAgent() async {
            logger.log("utils.installLaunchAgent: creating Launch Agent plist", type: .default)
            let fileContent = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>mac.ibm.shift</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>/Applications/\(Bundle.main.name).app</string>
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
            do {
                // `~/Library/LaunchAgents` doesn't exist on a fresh user account, and
                // `FileManager.createFile` silently fails when the folder is missing.
                try FileManager.default.createDirectory(at: launchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileContent.write(to: launchAgentURL, atomically: true, encoding: .utf8)
            } catch {
                logger.log("utils.installLaunchAgent: failed to write Launch Agent plist -> \"\(error.localizedDescription)\"", type: .error)
                return
            }
            logger.log("utils.installLaunchAgent: loading Launch Agent", type: .default)
            await withCheckedContinuation { continuation in
                var errors: NSDictionary?
                _ = NSAppleScript(source: "do shell script \"launchctl bootstrap gui/\(getuid()) \(launchAgentURL.path) \"")?.executeAndReturnError(&errors)
                if let errors {
                    logger.log("utils.installLaunchAgent: launchctl bootstrap returned an error -> \"\(errors)\"", type: .error)
                }
                continuation.resume()
            }
            logger.log("utils.installLaunchAgent: Launch Agent installed", type: .default)
        }

        /// Remove the Launch Agent from the device.
        static func removeLaunchAgent() async {
            logger.log("utils.removeLaunchAgent: unloading Launch Agent", type: .default)
            await withCheckedContinuation { continuation in
                var errors: NSDictionary?
                _ = NSAppleScript(source: "do shell script \"launchctl bootout gui/\(getuid()) \(launchAgentURL.path) \"")?.executeAndReturnError(&errors)
                if let errors {
                    logger.log("utils.removeLaunchAgent: launchctl bootout returned an error -> \"\(errors)\"", type: .error)
                }
                continuation.resume()
            }
            logger.log("utils.removeLaunchAgent: removing Launch Agent plist", type: .default)
            do {
                try FileManager.default.removeItem(at: launchAgentURL)
                logger.log("utils.removeLaunchAgent: Launch Agent removed", type: .default)
            } catch {
                logger.log("utils.removeLaunchAgent: failed to remove Launch Agent plist -> \"\(error.localizedDescription)\"", type: .error)
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
        /// Logger instance.
        private static let logger = MLogger.main.scoped(to: .migration)

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
            let provider: String?

            if path.contains("/Library/Mobile Documents/com~apple~CloudDocs/") {
                provider = "iCloud Drive"
            } else if path.contains("/Library/Mobile Documents/") {
                let components = path.components(separatedBy: "/")
                if let index = components.firstIndex(of: "Mobile Documents"),
                   index + 1 < components.count,
                   components[index + 1].contains("~") {
                    provider = "iCloud app container"
                } else {
                    provider = nil
                }
            } else if path.contains("/OneDrive") || path.contains("/OneDrive - ") {
                provider = "OneDrive"
            } else if path.contains("/Box/") || path.contains("/Box Sync/") {
                provider = "Box"
            } else if path.contains("/Dropbox/") {
                provider = "Dropbox"
            } else if path.contains("/Google Drive/") || path.contains("/Google Drive File Stream/") || path.contains("/Google/DriveFS/") {
                provider = "Google Drive"
            } else if path.contains("/pCloud Drive/") {
                provider = "pCloud"
            } else if path.contains("/Sync/") {
                provider = "Sync.com"
            } else if path.contains("/MEGA/") {
                provider = "MEGA"
            } else if path.contains("/iCloud Drive") || path.contains("/iCloud/") {
                provider = "iCloud Drive symlink"
            } else if let resourceValues = try? pathURL.resourceValues(forKeys: [.isUbiquitousItemKey]),
                      let isUbiquitousItem = resourceValues.isUbiquitousItem, isUbiquitousItem {
                provider = "iCloud ubiquitous item"
            } else {
                provider = nil
            }

            guard let provider else { return false }
            logger.log("utils.isCloudSyncedPath: \(provider) detected -> \"\(path)\"")
            return true
        }
        // swiftlint:enable function_body_length

        /// `SF_DATALESS` from `<sys/stat.h>`: the item is a File Provider placeholder (e.g. an iCloud
        /// Drive file evicted by "Optimize Mac Storage") whose content isn't stored locally.
        private static let datalessFlag: UInt32 = 0x4000_0000

        /// Checks whether an item is a dataless placeholder. Reading one makes the system download it
        /// from the cloud, which is slow, needs network access and can fill the source's disk, so
        /// such items must never be read during a migration.
        /// - Parameter pathURL: The URL to check. Symbolic links are not followed.
        /// - Returns: True if the item (file or directory) is dataless, false otherwise.
        static func isDatalessItem(_ pathURL: URL) -> Bool {
            guard let info = lstatInfo(pathURL) else { return false }
            return info.st_flags & datalessFlag != 0
        }

        /// Checks whether an item is neither a regular file, a directory nor a symbolic link: a named
        /// pipe (FIFO), socket or device node. Their content can't be copied, and opening a FIFO for
        /// reading blocks until another process opens it for writing - which, on the main actor,
        /// freezes the whole app (e.g. the `*.cv` and `*.note` pipes Realm databases keep next to
        /// their data).
        /// - Parameter pathURL: The URL to check. Symbolic links are not followed.
        /// - Returns: True if the item is a special file, false otherwise (or if it can't be read).
        static func isSpecialFile(_ pathURL: URL) -> Bool {
            guard let info = lstatInfo(pathURL) else { return false }
            return isSpecialFile(info)
        }

        private static func isSpecialFile(_ info: stat) -> Bool {
            switch info.st_mode & 0o170000 {
            case 0o100000, 0o040000, 0o120000: // regular file, directory, symbolic link
                return false
            default:
                return true
            }
        }

        private static func lstatInfo(_ pathURL: URL) -> stat? {
            var info = stat()
            return lstat(pathURL.path, &info) == 0 ? info : nil
        }

        /// Checks whether a path is inside an application bundle (`Something.app/...`).
        ///
        /// Bundles are copied whole: removing anything from inside one (a nested `node_modules`, a
        /// cache folder...) can leave the application broken on the destination.
        ///
        /// A macOS bundle always has a `Contents` folder (or `Wrapper`, for iOS apps) directly under the
        /// `.app` folder, which is what is looked for: a plain `.app/` match would also catch container
        /// folders named after a bundle identifier, such as `Containers/com.example.app/Data/...`.
        /// - Parameter pathURL: The URL to check.
        /// - Returns: True if one of the parent folders of the item is an `.app` bundle.
        static func isInsideAppBundle(_ pathURL: URL) -> Bool {
            let path = pathURL.path
            return path.contains(".app/Contents") || path.contains(".app/Wrapper")
        }

        /// Checks whether a path is a cache or temporary folder that the owning app regenerates on
        /// its own: `Library/Caches` (in the user library, a container or a group container) and a
        /// container's `Data/tmp`. Transferring them only costs time and space on the destination.
        /// Nothing inside an application bundle is considered regenerable.
        /// - Parameter pathURL: The URL to check.
        /// - Returns: True if the path is one of those folders, false otherwise.
        static func isRegenerableCachePath(_ pathURL: URL) -> Bool {
            guard !isInsideAppBundle(pathURL) else { return false }
            let components = pathURL.standardizedFileURL.pathComponents
            guard components.count >= 2 else { return false }
            let name = components[components.count - 1]
            let parent = components[components.count - 2]
            if name == "Caches" && parent == "Library" {
                return true
            }
            return name == "tmp" && parent == "Data" && components.contains("Containers")
        }

        /// Determines whether an item must be left out of the transfer because it can't or shouldn't
        /// be copied (dataless placeholder, named pipe, socket or device node) or is regenerable by
        /// the destination (cache/tmp folder). Applies to every item, regardless of the
        /// user-configurable exclusion rules.
        /// - Parameter pathURL: The URL to check.
        /// - Returns: True if the item should be skipped, false otherwise.
        static func shouldSkipForTransfer(_ pathURL: URL) -> Bool {
            if isRegenerableCachePath(pathURL) {
                return true
            }
            guard let info = lstatInfo(pathURL) else { return false }
            return info.st_flags & datalessFlag != 0 || isSpecialFile(info)
        }

        /// Checks an item's name against the excluded file extensions and name prefixes.
        /// - Parameters:
        ///   - pathURL: The URL to check.
        ///   - extensions: The excluded file extensions.
        ///   - prefixes: The excluded file name prefixes (a name equal to a prefix also matches).
        /// - Returns: True if the item's name matches one of the rules, false otherwise.
        static func matchesExcludedNameRules(_ pathURL: URL, extensions: [String], prefixes: [String]) -> Bool {
            let ext = pathURL.pathExtension
            if !ext.isEmpty && extensions.contains(ext) {
                return true
            }
            let fileName = pathURL.lastPathComponent
            return prefixes.contains(where: { fileName.hasPrefix($0) || fileName == $0 })
        }

        /// The configured extension and prefix rules, read once: a transfer applies them to every item
        /// of every selected folder, so they can't be re-read from the managed defaults each time.
        private static let transferExcludedExtensions = AppContext.excludedFileExtensions
        private static let transferExcludedPrefixes = AppContext.excludedFilePrefixes

        /// Determines whether an item found *inside* a selected folder must be left out of the transfer.
        ///
        /// The scanner only applies the exclusion rules to the first levels of a selected folder, so
        /// anything deeper (e.g. a nested `node_modules`, `.DS_Store` or VM disk image) was previously
        /// sent regardless. This applies `shouldSkipForTransfer` plus the managed extension and prefix
        /// rules at every depth. It deliberately leaves out:
        /// - the URL exclusion list (`~/Library`, dotfolders...), which describes top-level locations
        ///   and would drop files the user selected on purpose;
        /// - the cloud path name heuristics (`/Box/`, `/Sync/`...), which would match ordinary folders
        ///   with those names. Cloud-synced folders are detected through the system's ubiquity flag.
        ///
        /// Nothing inside an application bundle is excluded by name (see `isInsideAppBundle`): an app's
        /// own `node_modules` is part of the app.
        /// - Parameter pathURL: The URL of the item inside a selected folder.
        /// - Returns: True if the item (and everything below it) should be skipped, false otherwise.
        static func shouldSkipDescendantForTransfer(_ pathURL: URL) -> Bool {
            if isInsideAppBundle(pathURL) {
                return false
            }
            if shouldSkipForTransfer(pathURL) {
                return true
            }
            if matchesExcludedNameRules(pathURL, extensions: transferExcludedExtensions, prefixes: transferExcludedPrefixes) {
                return true
            }
            // Only directories are checked: a cloud-synced item always sits in a cloud-synced
            // directory, so pruning the directory covers its contents without a lookup per file.
            let values = try? pathURL.resourceValues(forKeys: [.isDirectoryKey, .isUbiquitousItemKey])
            return values?.isDirectory == true && values?.isUbiquitousItem == true
        }

        /// Determines whether a given path should be ignored during file operations.
        /// - Parameters:
        ///   - pathURL: The URL to check against exclusion rules.
        ///   - ignoringURLExclusions: When true, the URL exclusion list (e.g. `~/Library`) is skipped;
        ///     cloud-sync, extension and prefix rules still apply. Used for app support files that
        ///     discovery explicitly picked, which live inside otherwise-excluded folders.
        /// - Returns: True if the path should be ignored, false otherwise.
        static func shouldIgnorePath(_ pathURL: URL, ignoringURLExclusions: Bool = false) -> Bool {
            if isCloudSyncedPath(pathURL) || shouldSkipForTransfer(pathURL) {
                return true
            }
            
            if matchesExcludedNameRules(pathURL,
                                        extensions: AppContext.excludedFileExtensions,
                                        prefixes: AppContext.excludedFilePrefixes) {
                return true
            }
            
            guard !ignoringURLExclusions else { return false }
            
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
        
        /// Calculates the total size of a directory recursively
        /// - Parameter url: The directory URL to calculate size for
        /// - Returns: Total size in bytes
        static func calculateDirectorySize(_ url: URL) -> Int {
            var isDirectory: ObjCBool = false
            guard !shouldSkipForTransfer(url),
                  FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                return 0
            }
            
            // If it's a file, return its size
            if !isDirectory.boolValue {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let fileSize = attributes[.size] as? Int {
                    return fileSize
                }
                return 0
            }
            
            // If it's a directory, calculate recursively
            var totalSize = 0
            
            if let enumerator = FileManager.default.enumerator(at: url,
                                                               includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                                                               options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    if shouldSkipDescendantForTransfer(fileURL) {
                        enumerator.skipDescendants()
                        continue
                    }
                    do {
                        let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                        
                        // Only add size for files, not directories
                        if let isDirectory = resourceValues.isDirectory, !isDirectory {
                            if let fileSize = resourceValues.fileSize {
                                totalSize += fileSize
                            }
                        }
                    } catch {
                        logger.log("utils.calculateDirectorySize: failed to read file size for \"\(fileURL.path)\" -> \"\(error)\"")
                    }
                }
            }
            
            return totalSize
        }
        
        /// Counts the number of files in a directory recursively
        /// - Parameter url: The directory URL to count files in
        /// - Returns: Total number of files (not including directories)
        static func countFilesInDirectory(_ url: URL) -> Int {
            var isDirectory: ObjCBool = false
            guard !shouldSkipForTransfer(url),
                  FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                return 0
            }
            
            // If it's a file, return 1
            if !isDirectory.boolValue {
                return 1
            }
            
            // If it's a directory, count recursively
            var fileCount = 0
            
            if let enumerator = FileManager.default.enumerator(at: url,
                                                               includingPropertiesForKeys: [.isDirectoryKey],
                                                               options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    if shouldSkipDescendantForTransfer(fileURL) {
                        enumerator.skipDescendants()
                        continue
                    }
                    do {
                        let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
                        
                        // Only count files, not directories
                        if let isDirectory = resourceValues.isDirectory, !isDirectory {
                            fileCount += 1
                        }
                    } catch {
                        logger.log("utils.countFilesInDirectory: failed to check file type for \"\(fileURL.path)\" -> \"\(error)\"")
                    }
                }
            }
            
            return fileCount
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
        private static let customizedKeys: [String] = Array(UserDefaults.standard.dictionaryRepresentation().keys)

        /// Registers default values for all managed configuration keys so that every key
        /// is present in `UserDefaults.standard.dictionaryRepresentation()` before the first
        /// call to `managedValue(forKey:)` initialises `customizedKeys`.
        ///
        /// Must be called once at app startup — before any view body or managed property
        /// is evaluated — so that `customizedKeys` captures the complete set of managed keys.
        ///
        /// `register(defaults:)` writes into the *registration domain*, the lowest-priority
        /// domain. Any explicitly set value (e.g. from an MDM profile or a developer override)
        /// will still shadow the registered value.
        static func registerManagedDefaults() {
            UserDefaults.standard.register(defaults: [
                "skipMDMCheck":                 false,
                "skipAppleIDCheck":             false,
                "skipJamfRecon":                false,
                "jamfReconMethod":              "selfServicePolicy",
                "duplicateFilesHandlingPolicy": "move",
                "excludedPathsList":            [String](),
                "allowedPathsList":             [String](),
                "excludedFileExtensions":       [String](),
                "excludedFilePrefixes":         [String](),
                "mdmEnvironments":              [[String: Any]](),
                "orgName":                      "Mac@IBM",
                "networkServiceIdentifier":     "_migrator",
                "enrollmentRedirectionLink":    "https://setupmydevice.ibm.com",
                "privacyPolicyURL":             "http://www.ibm.com/privacy",
                "termsConditionsURL":           "T&C.pdf",
                "thirdPartyNotices":            "TPNotices.pdf",
                "shouldRequireTAndCAcceptance": false,
                "skipMigrationSummary":         false,
                "showWelcomePageInfo":          false,
                "generateReport":              false,
                "checkAppsArchitecture":        true,
                "customFontFamily":             "IBMPlexSans",
                "migrateAppSupportFiles":       true,
                "migratePreferences":           true,
                "migrationPresets":             [[String: Any]](),
                "excludeApplicationsFolder":    false
            ])
        }
        
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
        static func isDefaultsValueAcceptable(forKey key: String, suiteName: String? = nil) -> Bool {
#if DEBUG
            return true
#else
            if let suiteName = suiteName {
                return UserDefaults(suiteName: suiteName)?.objectIsForced(forKey: key) ?? false
            } else {
                return UserDefaults.standard.objectIsForced(forKey: key)
            }
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
        static func managedValue<T>(forKey key: String, suiteName: String? = nil, defaultValue: T) -> T {
            if let suiteName = suiteName {
                guard Self.isDefaultsValueAcceptable(forKey: key, suiteName: suiteName) else {
                    return defaultValue
                }
                return UserDefaults(suiteName: suiteName)?.value(forKey: key) as? T ?? defaultValue
            } else {
                guard customizedKeys.contains(key) && Self.isDefaultsValueAcceptable(forKey: key) else {
                    return defaultValue
                }
                return UserDefaults.standard.value(forKey: key) as? T ?? defaultValue
            }
        }
    }
}

// swiftlint:enable file_length nesting
