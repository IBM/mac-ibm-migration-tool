//
//  AppContext.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 09/09/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

struct AppContext {
    
    // MARK: - Default Values for Customisable Constants
    
    /// The name used to refer the organization that manage the device.
    /// Managed setting available using `orgName` defaults key.
    private static let fallbackOrgName: String = "<Organization Name>"
    
    /// Path the Jamf Self Service .app
    /// Managed setting available using `storePath` defaults key.
    private static let fallbackStorePath: String = "<Store Path>"
    
    /// A list of managed environments to be tracked on the user's device.
    /// Each `ManagedEnvironment` includes:
    /// - `name`: The environment's name (e.g., Production, QA).
    /// - `serverURL`: The server URL used to identify the environment through the installed management profile. The `serverURL` can optionally include the `/mdm/ServerURL` suffix, and will be added if missing.
    /// - `reconPolicyID`: The policy ID required to run an inventory update via Jamf Self Service.
    /// This workflow is specifically designed for devices managed by Jamf Pro.
    /// Managed setting available using `mdmEnvironments` defaults key.
    private static let fallbackMdmEnvironments: [ManagedEnvironment] = []
    
    /// The service identifier used to discover and connect to network services via Bonjour (DNS-SD).
    /// Managed setting available using `networkServiceIdentifier` defaults key.
    private static let fallbackNetworkServiceIdentifier: String = "<Service Identifier>"

    /// A URL to redirect users to setup instructions if the app detects the device is not managed by MDM.
    /// Managed setting available using `enrollmentRedirectionLink` defaults key.
    private static let fallbackEnrollmentRedirectionLink: String = "<Enrollment Redirection Link>"

    /// Path to the folder that will contains duplicate files in case duplicateFilesHandlingPolicy is set to `move`.
    /// Managed setting available using `backupPath` defaults key.
    private static let fallbackBackupPath: String = "<Backup Path>"
    
    /// Flag that defines whether or not to check the device's management state and if it's enrolled in a recognised environment.
    /// Managed setting available using `skipMDMCheck` defaults key.
    private static let fallbackShouldSkipMDMCheck: Bool = false
    
    /// Flag that determines whether or not to display the post-migration phase for Apple ID login verification.
    /// Managed setting available using `skipAppleIDCheck` defaults key.
    private static let fallbackShouldSkipAppleIDCheck: Bool = false
    
    /// Flag that specifies whether or not to perform an inventory update to Jamf Pro.
    /// Managed setting available using `skipJamfRecon` defaults key.
    private static let fallbackShouldSkipJamfRecon: Bool = false
    
    /// Specifies what method to use to run the Jamf inventory update.
    /// Managed setting available using `jamfReconMethod` defaults key.
    private static let fallbackJamfReconMethod: JamfReconMethod = .selfServicePolicy
    
    /// Path to the folder that will contains duplicate files in case duplicateFilesHandlingPolicy is set to `move`.
    /// Managed setting available using `duplicateFilesHandlingPolicy` defaults key.
    private static let fallbackDuplicateFilesHandlingPolicy: DuplicateFilesHandlingPolicy = .overwrite
    
    // MARK: - Default File Scan Variables
    
    /// Custom list of paths that needs to be ignored during file discovery.
    static var defaultUrlExclusionList: [URL?] = [FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first,
                                                  FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent("\(Bundle.main.name).app"),
                                                  FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent("Numbers.app"),
                                                  FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent("Pages.app"),
                                                  FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent("Keynote.app"),
                                                  FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent("Safari.app"),
                                                  FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent("Utilities"),
                                                  FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent("Xcode.app"),
                                                  FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first]
    
    /// Custom list of explicitely allowed paths that needs to be included during file discovery.
    static var defaultExplicitAllowList: [URL?] = [FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
                                                   FileManager.default.urls(for: .applicationScriptsDirectory, in: .userDomainMask).first,
                                                   FileManager.default.urls(for: .preferencePanesDirectory, in: .userDomainMask).first,
                                                   FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Preferences", conformingTo: .directory)]
    
    /// Custom list of file's name that needs to be ignored during file discovery.
    static var defaultExcludedFileExtensions: [String] = [".DS_Store",
                                                          ".localized",
                                                          ".vdi",
                                                          ".vbox"]
    
    // MARK: - User Defaults Keys

    /// The array of keys defined in the UserDefaults domain.
    private static let customizedKeys: Dictionary<String, Any>.Keys = UserDefaults.standard.dictionaryRepresentation().keys
    
    /// UserDefaults key representing the logging verbosity level. Possible values:
    /// - `noLog`: No logs are written.
    /// - `standard`: A standard amount of logs are written.
    /// - `debug`: A verbose log level used for debugging migration issues. This may generate large log files during migration. Use cautiously.
    private static let loggingLevelUserDefaultsKey: String = "loggingLevel"

    /// UserDefaults key indicating whether the device is in the post-reboot phase during migration.
    /// This key is managed automatically by the app, and manual changes should be avoided.
    private static let postRebootUserDefaultsKey: String = "postRebootPhase"

    /// UserDefaults key indicating whether the app should skip device management checks.
    /// If true, the app won't check if the device is managed or trigger Jamf recon after migration.
    private static let skipMDMCheckUserDefaultsKey: String = "skipMDMCheck"

    /// UserDefaults key indicating whether the app should skip the Apple ID login step after migration.
    private static let skipAppleIDCheckUserDefaultsKey: String = "skipAppleIDCheck"

    /// UserDefaults key indicating whether the app should skip the Jamf Inventory Update step after migration.
    private static let skipJamfReconUserDefaultsKey: String = "skipJamfRecon"
    
    /// UserDefaults key indicating how to run Jamf Inventory Uodate..
    private static let jamfReconMethodUserDefaultsKey: String = "jamfReconMethod"
    
    /// UserDefaults key indicating which policy to use fo handle duplicate files on the destination device.
    private static let duplicateFilesHandlingPolicyKey: String = "duplicateFilesHandlingPolicy"
    
    /// UserDefaults key indicating whether the app should skip the device reboot step after migration.
    static let skipRebootUserDefaultsKey: String = "skipDeviceReboot"

    /// UserDefaults key indicating the list of paths to exclude during file discovery.
    private static let excludedPathsListKey: String = "excludedPathsList"
    
    /// UserDefaults key indicating the list of paths to explicitely allow during file discovery.
    private static let allowedPathsListKey: String = "allowedPathsList"
    
    /// UserDefaults key indicating the list of excluded file extensions during file discovery.
    private static let excludedFileExtensionsKey: String = "excludedFileExtensions"
    
    /// UserDefaults key indicating the list of managed environments.
    private static let mdmEnvironmentsUserDefaultsKey: String = "mdmEnvironments"
    
    /// UserDefaults key used to pull managed setting defining the Jamf Self Service app path.
    private static let storePathKey: String = "storePath"
    
    /// UserDefaults key used to pull managed setting defining the bonjour service identifier.
    private static let networkServiceIdentifierKey: String = "networkServiceIdentifier"
    
    /// UserDefaults key used to pull managed setting defining the path to the backup folder.
    private static let backupPathKey: String = "backupPath"
    
    /// UserDefaults key used to pull managed setting defining the organization name used to brand the app.
    private static let orgNameKey: String = "orgName"
    
    /// UserDefaults key used to pull managed setting defining the redirection link to the device enrollment instructions.
    private static let enrollmentRedirectionLinkKey: String = "enrollmentRedirectionLink"
    
    // MARK: - Final Computed Properties
    
    static var loggingLevel: MLogger.LogLevel {
        return MLogger.LogLevel(rawValue: UserDefaults.standard.string(forKey: Self.loggingLevelUserDefaultsKey) ?? "standard") ?? .standard
    }
    static var isPostRebootPhase: Bool {
        get {
            return UserDefaults.standard.bool(forKey: Self.postRebootUserDefaultsKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: Self.postRebootUserDefaultsKey)
            UserDefaults.standard.synchronize()
        }
    }
    static var shouldSkipMDMCheck: Bool {
        guard Self.customizedKeys.contains(Self.skipMDMCheckUserDefaultsKey) else {
            return Self.fallbackShouldSkipMDMCheck
        }
        return UserDefaults.standard.bool(forKey: Self.skipMDMCheckUserDefaultsKey)
    }
    static var shouldSkipAppleIDCheck: Bool {
        guard Self.customizedKeys.contains(Self.skipAppleIDCheckUserDefaultsKey) else {
            return Self.fallbackShouldSkipAppleIDCheck
        }
        return UserDefaults.standard.bool(forKey: Self.skipAppleIDCheckUserDefaultsKey)
    }
    static var shouldSkipJamfRecon: Bool {
        guard Self.customizedKeys.contains(Self.skipJamfReconUserDefaultsKey) else {
            return Self.fallbackShouldSkipJamfRecon
        }
        return UserDefaults.standard.bool(forKey: Self.skipJamfReconUserDefaultsKey)
    }
    static var jamfReconMethod: JamfReconMethod {
        guard let value = UserDefaults.standard.string(forKey: Self.jamfReconMethodUserDefaultsKey),
              let method = JamfReconMethod(rawValue: value) else {
            return Self.fallbackJamfReconMethod
        }
        return method
    }
    static var shouldSkipDeviceReboot: Bool {
        return UserDefaults.standard.bool(forKey: Self.skipRebootUserDefaultsKey)
    }
    static var duplicateFilesHandlingPolicy: DuplicateFilesHandlingPolicy {
        guard let value = UserDefaults.standard.string(forKey: Self.duplicateFilesHandlingPolicyKey),
              let policy = DuplicateFilesHandlingPolicy(rawValue: value) else {
            return Self.fallbackDuplicateFilesHandlingPolicy
        }
        return policy
    }
    static var managedExcludedURLs: [URL?] {
        return (UserDefaults.standard.array(forKey: Self.excludedPathsListKey) as? [String] ?? []).compactMap { urlString in
            return Utils.parseProfileURL(urlString)
        }
    }
    static var urlExclusionList: [URL?] {
        return managedExcludedURLs + defaultUrlExclusionList
    }
    static var managedAllowedURLs: [URL?] {
        return (UserDefaults.standard.array(forKey: Self.allowedPathsListKey) as? [String] ?? []).compactMap { urlString in
            return Utils.parseProfileURL(urlString)
        }
    }
    static var explicitAllowList: [URL?] {
        return managedAllowedURLs + defaultExplicitAllowList
    }
    static var excludedFileExtensions: [String] {
        let managedExcludedFileExtensions = UserDefaults.standard.array(forKey: Self.allowedPathsListKey) as? [String] ?? []
        return managedExcludedFileExtensions + defaultExcludedFileExtensions
    }
    static var mdmEnvironments: [ManagedEnvironment] {
        guard let managedEnvironments = UserDefaults.standard.array(forKey: mdmEnvironmentsUserDefaultsKey) as? [[String: String]],
              !managedEnvironments.isEmpty else {
            return fallbackMdmEnvironments
        }
        
        return managedEnvironments.compactMap { try? DictionaryDecoder().decode(ManagedEnvironment.self, from: $0) }
    }
    static var storePath: String {
        if let jamfValue = UserDefaults(suiteName: "com.jamfsoftware.jamf")?.string(forKey: "self_service_app_path") {
            return jamfValue
        }
        return UserDefaults.standard.string(forKey: Self.storePathKey) ?? fallbackStorePath
    }
    static var orgName: String {
        return UserDefaults.standard.string(forKey: Self.orgNameKey) ?? fallbackOrgName
    }
    static var backupPath: String {
        return UserDefaults.standard.string(forKey: Self.backupPathKey) ?? (fallbackBackupPath.isEmpty && fallbackBackupPath != "<Backup Path>" ? fallbackBackupPath : "\(FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!.relativePath)/Migration.Backup")
    }
    static var networkServiceIdentifier: String {
        return UserDefaults.standard.string(forKey: Self.networkServiceIdentifierKey) ?? fallbackNetworkServiceIdentifier
    }
    static var enrollmentRedirectionLink: String {
        return UserDefaults.standard.string(forKey: Self.enrollmentRedirectionLinkKey) ?? fallbackEnrollmentRedirectionLink
    }
}
