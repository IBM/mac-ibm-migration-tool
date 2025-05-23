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
    
    // MARK: - Branding Constants
    
    static let orgName: String = "Company"
    
    /// Path to the folder that will contains duplicate files in case duplicateFilesHandlingPolicy is set to `move`.
    static let backupPath: String = "\(FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!.relativePath)/Migration.Backup"
    
    // MARK: - Network Constants

    /// The service identifier used to discover and connect to network services via Bonjour (DNS-SD).
    static let networkServiceIdentifier: String = "_migrator._tcp"

    // MARK: - Device Management Related Constants

    /// UserDefaults key indicating the list of managed environments.
    private static let mdmEnvironmentsUserDefaultsKey: String = "mdmEnvironments"

    /// A list of managed environments to be tracked on the user's device.
    /// Each `ManagedEnvironment` includes:
    /// - `name`: The environment's name (e.g., Production, QA).
    /// - `serverURL`: The server URL used to identify the environment through the installed management profile.
    ///     The `serverURL` can optionally include the `/mdm/ServerURL` suffix, and will be added if missing.
    /// - `reconPolicyID`: The policy ID required to run an inventory update via Jamf Self Service.
    /// This workflow is specifically designed for devices managed by Jamf Pro.
    static let fallbackMdmEnvironments: [ManagedEnvironment] = [
        ManagedEnvironment(name: "TestExample", serverURL: "https://test.url/mdm/ServerURL", reconPolicyID: "022"),
        ManagedEnvironment(name: "ProdExample", serverURL: "https://prod.url/mdm/ServerURL", reconPolicyID: "033")
    ]

    /// Read the list of managed environments from UserDefaults with the
    static var mdmEnvironments: [ManagedEnvironment] {
        let managedEnvironments = UserDefaults.standard.array(forKey: mdmEnvironmentsUserDefaultsKey) as? [[String: String]] ?? []

        /// Use managedEnvironments if not empty, otherwise fallback to fallbackMdmEnvironments
        return managedEnvironments.isEmpty ? fallbackMdmEnvironments : managedEnvironments.compactMap { dict in
            guard
                let name = dict["name"],
                let serverURL = dict["serverURL"],
                let reconPolicyID = dict["reconPolicyID"]
            else {
                return nil
            }

            return ManagedEnvironment(name: name, serverURL: serverURL, reconPolicyID: reconPolicyID)
        }
    }

    /// Path the Jamf Self Service .app
    static let fallbackStorePath: String = "/Applications/Company Self Service.app"

    /// Returns the path to the Jamf Self Service .app configured on the user's device OR the fallbackStorePath
    /// Reads the plist at /Library/Preferences/com.jamfsoftware.jamf.plist to get the path.
    static var storePath: String {
        let jamfUserDefaults = UserDefaults(suiteName: "com.jamfsoftware.jamf")
        let jamfSelfServicePath = jamfUserDefaults?.string(forKey: "self_service_app_path")
        return jamfSelfServicePath ?? fallbackStorePath
    }

    /// A URL to redirect users to setup instructions if the app detects the device is not managed by MDM.
    static let enrollmentRedirectionLink: String = "https://url.to.enrollment/support.website"

    // MARK: - User Defaults Keys

    /// UserDefaults key representing the logging verbosity level. Possible values:
    /// - `noLog`: No logs are written.
    /// - `standard`: A normal amount of logs are written.
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

    /// UserDefaults key indicating the list of paths to exclude during file discovery
    private static let excludedPathsListKey: String = "excludedPathsList"

    /// UserDefaults key indicating whether the app should skip the device reboot step after migration.
    static let skipRebootUserDefaultsKey: String = "skipDeviceReboot"
    
    // MARK: - User Defaults Values
    
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
        return UserDefaults.standard.bool(forKey: Self.skipMDMCheckUserDefaultsKey)
    }
    static var shouldSkipAppleIDCheck: Bool {
        return UserDefaults.standard.bool(forKey: Self.skipAppleIDCheckUserDefaultsKey)
    }
    static var shouldSkipJamfRecon: Bool {
        return UserDefaults.standard.bool(forKey: Self.skipJamfReconUserDefaultsKey)
    }
    static var jamfReconMethod: JamfReconMethod {
        return JamfReconMethod(rawValue: UserDefaults.standard.string(forKey: Self.jamfReconMethodUserDefaultsKey) ?? "selfServicePolicy") ?? .selfServicePolicy
    }
    static var shouldSkipDeviceReboot: Bool {
        return UserDefaults.standard.bool(forKey: Self.skipRebootUserDefaultsKey)
    }
    static var duplicateFilesHandlingPolice: DuplicateFilesHandlingPolicy {
        return DuplicateFilesHandlingPolicy(rawValue: UserDefaults.standard.string(forKey: Self.duplicateFilesHandlingPolicyKey) ?? "overwrite") ?? .overwrite
    }
    static var urlExclusionList: [URL?] {
        let managedExcludedPaths = UserDefaults.standard.array(forKey: Self.excludedPathsListKey) as? [String] ?? []
        let managedExcludedURLs = managedExcludedPaths.compactMap { URL(string: $0) }
        return managedExcludedURLs + defaultUrlExclusionList
    }

    // MARK: - File Scan Variables

    /// Custom list of paths that needs to be ignored during file discovery.
    static var defaultUrlExclusionList: [URL?] = [FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first,
                                           FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent("\(Bundle.main.name).app"),
                                           FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent("Numbers.app"),
                                           FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent("Pages.app"),
                                           FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent("Keynote.app"),
                                           FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent("Box.app"),
                                           FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent("Safari.app"),
                                           FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent("Cisco"),
                                           FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent("Utilities"),
                                           FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent("Xcode.app"),
                                           FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first]
    
    /// Custom list of explicitely allowed paths that needs to be included during file discovery.
    static var explicitAllowList: [URL?] = [FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
                                            FileManager.default.urls(for: .applicationScriptsDirectory, in: .userDomainMask).first,
                                            FileManager.default.urls(for: .preferencePanesDirectory, in: .userDomainMask).first,
                                            FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Preferences", conformingTo: .directory)]
    /// Custom list of file's name that needs to be ignored during file discovery.
    static var excludedFiles: [String] = [".DS_Store",
                                          ".localized",
                                          ".vdi",
                                          ".vbox"]
}
