//
//  AppContext.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 09/09/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//
// swiftlint:disable file_length

import Foundation

/// `AppContext` serves as the centralized location for all application and migration-related configuration, default values, UserDefaults keys, and managed settings.
///
/// This struct acts as the single source of truth for retrieving and managing customizable constants, fallback values, and dynamic settings for the app's environment. It provides:
/// - Default values for organization branding, managed environments, and external resource links.
/// - Centralized management of file scanning rules (exclusion/inclusion lists, file extensions and prefixes).
/// - Computed properties that transparently handle managed configuration via UserDefaults or fallback to defaults.
/// - Central access to UserDefaults keys and behaviors for logging, migration phase state, reboot logic, and Jamf integration.
/// - Access to legal and informational resources such as privacy policies and third-party notices.
///
/// All static properties are intended for global and consistent usage across the app, ensuring that configuration changes are easily managed and that the app remains adaptable to both managed and unmanaged deployment scenarios.
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
    private static let fallbackDuplicateFilesHandlingPolicy: DuplicateFilesHandlingPolicy = .move
    
    /// The URL string pointing to the app's privacy policy.
    /// - If the string is a valid remote URL (e.g., starts with "http://" or "https://"), it will be used to open the policy in a web browser.
    /// - If the string is a relative file path (e.g., "PrivacyPolicy.pdf"), it will be resolved to a local resource within the app bundle's "Contents/Resources" directory.
    private static let fallbackPrivacyPolicyURL: String = ""
    
    /// The URL string pointing to the app's terms and conditions.
    /// - If the string is a valid remote URL (e.g., starts with "http://" or "https://"), it will be used to open the t&c in a web browser.
    /// - If the string is a relative file path (e.g., "T&C.pdf"), it will be resolved to a local resource within the app bundle's "Contents/Resources" directory.
    private static let fallbackTermsConditionsURL: String = ""
    
    /// The URL string pointing to the app's third party notices.
    /// - If the string is a valid remote URL (e.g., starts with "http://" or "https://"), it will be used to open the notices in a web browser.
    /// - If the string is a relative file path (e.g., "TPNotices.pdf"), it will be resolved to a local resource within the app bundle's "Contents/Resources" directory.
    private static let fallbackThirdPartyNoticesURL: String = ""
    
    /// Flag that defines whether the app should require user acceptance of the Terms and Conditions.
    /// Managed setting available using `shouldRequireTAndCAcceptance` defaults key.
    private static let fallbackShouldRequireTAndCAcceptance: Bool = false
    
    /// Flag that specifies whether the app should show the Migration Summary view.
    /// Managed setting available using `skipMigrationSummary` defaults key.
    private static let fallbackShouldSkipMigrationSummary: Bool = false
    
    /// Flag that specifies whether the app should show the version/copyright/privacy information on the Welcome page.
    /// Managed setting available using `showWelcomePageInfo` defaults key.
    private static let fallbackShouldShowWelcomePageInfo: Bool = false
    
    /// Flag that specifies whether the app should generate the migration report on the user desktop.
    /// Managed setting available using `generateReportKey` defaults key.
    private static let fallbackShouldGenerateReport: Bool = false
    
    // MARK: - Default File Scan Variables
    
    /// Custom list of paths tha needs to be ignored during file discovery.
    static var defaultUrlExclusionList: [URL?] = [FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first,
                                                  FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent("\(Bundle.main.name).app"),
                                                  FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent("Numbers.app"),
                                                  FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent("Pages.app"),
                                                  FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent("Keynote.app"),
                                                  FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent("Safari.app"),
                                                  FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent("Utilities"),
                                                  FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.appendingPathComponent("Xcode.app"),
                                                  FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first,
                                                  FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("FileProvider")]
    
    /// Custom list of explicitely allowed paths that needs to be included during file discovery.
    static var defaultExplicitAllowList: [URL?] = [FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
                                                   FileManager.default.urls(for: .applicationScriptsDirectory, in: .userDomainMask).first,
                                                   FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Preferences", conformingTo: .directory)]
    
    /// Custom list of file's extensions that needs to be ignored during file discovery.
    static var defaultExcludedFileExtensions: [String] = ["vdi",
                                                          "vbox",
                                                          "img"]
    
    /// Custom list of file's name prefixes that needs to be ignored during file discovery.
    static var defaultExcludedFilePrefixes: [String] = ["MigrationReport_",
                                                        "~",
                                                        ".DS_Store",
                                                        ".localized"]
}

// MARK: - Non customizable elements

extension AppContext {
    
    // MARK: - Private User Defaults Keys
    
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
    
    /// UserDefaults key indicating the list of paths to exclude during file discovery.
    private static let excludedPathsListKey: String = "excludedPathsList"
    
    /// UserDefaults key indicating the list of paths to explicitely allow during file discovery.
    private static let allowedPathsListKey: String = "allowedPathsList"
    
    /// UserDefaults key indicating the list of excluded file extensions during file discovery.
    private static let excludedFileExtensionsKey: String = "excludedFileExtensions"
    
    /// UserDefaults key indicating the list of excluded file prefixes during file discovery.
    private static let excludedFilePrefixesKey: String = "excludedFilePrefixes"
    
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
    
    /// UserDefaults key used to pull managed setting defining the Privacy Policy URL String.
    private static let privacyPolicyURLKey: String = "privacyPolicyURL"
    
    /// UserDefaults key used to pull managed setting defining the Terms and Conditions URL String.
    private static let termsConditionsURLKey: String = "termsConditionsURL"
    
    /// UserDefaults key used to pull managed setting defining the Third Party Notices URL String.
    private static let thirdPartyNoticesKey: String = "thirdPartyNotices"
    
    /// UserDefaults key indicating whether the app should require user acceptance of the Terms and Conditions.
    private static let shouldRequireTAndCAcceptanceKey: String = "shouldRequireTAndCAcceptance"
    
    /// UserDefaults key indicating whether the app should skip the `Migration Summary` view.
    private static let skipMigrationSummaryKey: String = "skipMigrationSummary"
    
    /// UserDefaults key indicating whether the app should show version/copyright/privacy info on Welcome page.
    private static let showWelcomePageInfoKey: String = "showWelcomePageInfo"
    
    /// UserDefaults key indicating whether the app should generate the migration report on the user desktop.
    private static let generateReportKey: String = "generateReport"
    
    /// UserDefaults keys for custom page icons
    private static let welcomePageIconKey: String = "welcomePageIcon"
    private static let browserPageIconKey: String = "browserPageIcon"
    private static let serverPageIconKey: String = "serverPageIcon"
    private static let codeVerificationPageIconKey: String = "codeVerificationPageIcon"
    private static let setupPageIconKey: String = "setupPageIcon"
    private static let recapPageIconKey: String = "recapPageIcon"
    private static let migrationPageIconKey: String = "migrationPageIcon"
    private static let jamfReconPageIconKey: String = "jamfReconPageIcon"
    private static let rebootPageIconKey: String = "rebootPageIcon"
    private static let finalPageIconKey: String = "finalPageIcon"
    
    // MARK: - Public User Defaults Keys
    
    /// UserDefaults key indicating whether the app should skip the device reboot step after migration.
    static let skipRebootUserDefaultsKey: String = "skipDeviceReboot"
    
    /// UserDefaults key indicating whether the user accepted Terms and Conditions.
    static let tAndCUserAcceptanceKey: String = "tAndCUserAcceptance"
    
    // MARK: - Final Computed Properties
    
    static var loggingLevel: MLogger.LogLevel {
        return MLogger.LogLevel(rawValue: UserDefaults.standard.string(forKey: loggingLevelUserDefaultsKey) ?? "standard") ?? .standard
    }
    static var isPostRebootPhase: Bool {
        get {
            return UserDefaults.standard.bool(forKey: postRebootUserDefaultsKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: postRebootUserDefaultsKey)
            UserDefaults.standard.synchronize()
        }
    }
    static var shouldSkipMDMCheck: Bool {
        return Utils.UserDefaultsHelpers.managedValue(forKey: skipMDMCheckUserDefaultsKey, defaultValue: fallbackShouldSkipMDMCheck)
    }
    static var shouldSkipAppleIDCheck: Bool {
        return Utils.UserDefaultsHelpers.managedValue(forKey: skipAppleIDCheckUserDefaultsKey, defaultValue: fallbackShouldSkipAppleIDCheck)
    }
    static var shouldSkipJamfRecon: Bool {
        return Utils.UserDefaultsHelpers.managedValue(forKey: skipJamfReconUserDefaultsKey, defaultValue: fallbackShouldSkipJamfRecon)
    }
    static var jamfReconMethod: JamfReconMethod {
        guard let value = UserDefaults.standard.string(forKey: jamfReconMethodUserDefaultsKey),
              let method = JamfReconMethod(rawValue: value),
              Utils.UserDefaultsHelpers.isDefaultsValueAcceptable(forKey: jamfReconMethodUserDefaultsKey) else {
            return Self.fallbackJamfReconMethod
        }
        return method
    }
    static var shouldSkipDeviceReboot: Bool {
        return UserDefaults.standard.bool(forKey: skipRebootUserDefaultsKey)
    }
    static var duplicateFilesHandlingPolicy: DuplicateFilesHandlingPolicy {
        guard let value = UserDefaults.standard.string(forKey: duplicateFilesHandlingPolicyKey),
              let policy = DuplicateFilesHandlingPolicy(rawValue: value),
              Utils.UserDefaultsHelpers.isDefaultsValueAcceptable(forKey: duplicateFilesHandlingPolicyKey) else {
            return Self.fallbackDuplicateFilesHandlingPolicy
        }
        return policy
    }
    private static var managedExcludedURLs: [URL?] {
        return Utils.UserDefaultsHelpers.managedValue(forKey: excludedPathsListKey, defaultValue: []).compactMap { urlString in
            return Utils.Customization.parseProfileURL(urlString)
        }
    }
    static var urlExclusionList: [URL?] {
        return managedExcludedURLs + defaultUrlExclusionList
    }
    private static var managedAllowedURLs: [URL?] {
        return Utils.UserDefaultsHelpers.managedValue(forKey: allowedPathsListKey, defaultValue: []).compactMap { urlString in
            return Utils.Customization.parseProfileURL(urlString)
        }
    }
    static var explicitAllowList: [URL?] {
        return managedAllowedURLs + defaultExplicitAllowList
    }
    static var excludedFileExtensions: [String] {
        let managedExcludedFileExtensions =  Utils.UserDefaultsHelpers.managedValue(forKey: excludedFileExtensionsKey, defaultValue: []) as [String]
        return managedExcludedFileExtensions + defaultExcludedFileExtensions
    }
    static var excludedFilePrefixes: [String] {
        let managedExcludedFilePrefixes = Utils.UserDefaultsHelpers.managedValue(forKey: excludedFilePrefixesKey, defaultValue: []) as [String]
        return managedExcludedFilePrefixes + defaultExcludedFilePrefixes
    }
    static var mdmEnvironments: [ManagedEnvironment] {
        let managedEnvironments = Utils.UserDefaultsHelpers.managedValue(forKey: mdmEnvironmentsUserDefaultsKey,
                                                     defaultValue: [[:]]).compactMap { try? DictionaryDecoder().decode(ManagedEnvironment.self, from: $0) }
        return managedEnvironments.isEmpty ? fallbackMdmEnvironments : managedEnvironments
    }
    static var storePath: String {
        if let jamfValue = UserDefaults(suiteName: "com.jamfsoftware.jamf")?.string(forKey: "self_service_app_path") {
            return jamfValue
        }
        return Utils.UserDefaultsHelpers.isDefaultsValueAcceptable(forKey: storePathKey) ? UserDefaults.standard.string(forKey: storePathKey) ?? fallbackStorePath : fallbackStorePath
    }
    static var orgName: String {
        return Utils.UserDefaultsHelpers.managedValue(forKey: orgNameKey, defaultValue: fallbackOrgName)
    }
    static var backupPath: String {
        guard let path = UserDefaults.standard.string(forKey: backupPathKey), Utils.UserDefaultsHelpers.isDefaultsValueAcceptable(forKey: backupPathKey) else {
            return fallbackBackupPath.isEmpty && fallbackBackupPath != "<Backup Path>" ? fallbackBackupPath : "\(FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!.relativePath)/Migration.Backup"
        }
        return path
    }
    /// Returns the backup path relative to the user's home directory when possible
    static var relativeBackupPath: String {
        let fullPath = backupPath
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if fullPath.hasPrefix(homePath) {
            return "~" + fullPath.dropFirst(homePath.count)
        }
        return fullPath
    }
    static var networkServiceIdentifier: String {
        return Utils.UserDefaultsHelpers.managedValue(forKey: networkServiceIdentifierKey, defaultValue: fallbackNetworkServiceIdentifier)
    }
    static var enrollmentRedirectionLink: String {
        return Utils.UserDefaultsHelpers.managedValue(forKey: enrollmentRedirectionLinkKey, defaultValue: fallbackEnrollmentRedirectionLink)
    }
    static var privacyPolicyURL: URL? {
        let staticPrivacyPolicyURL = Utils.UserDefaultsHelpers.isDefaultsValueAcceptable(forKey: privacyPolicyURLKey) ? UserDefaults.standard.string(forKey: privacyPolicyURLKey) ?? fallbackPrivacyPolicyURL : fallbackPrivacyPolicyURL
        guard !staticPrivacyPolicyURL.isEmpty else { return nil }
        if staticPrivacyPolicyURL.isValidURL {
            return URL(string: staticPrivacyPolicyURL)
        } else {
            if #available(macOS 13.0, *) {
                let ppURL = URL(filePath: staticPrivacyPolicyURL, relativeTo: Bundle.main.bundleURL.appending(path: "Contents/Resources/"))
                guard let isReachable = try? ppURL.checkResourceIsReachable(), isReachable else { return nil }
                return ppURL
            } else {
                let ppURL = URL(fileURLWithPath: staticPrivacyPolicyURL, relativeTo: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/"))
                guard let isReachable = try? ppURL.checkResourceIsReachable(), isReachable else { return nil }
                return ppURL
            }
        }
    }
    static var termsConditionsURL: URL? {
        let staticTermsConditionsURL = Utils.UserDefaultsHelpers.isDefaultsValueAcceptable(forKey: termsConditionsURLKey) ? UserDefaults.standard.string(forKey: termsConditionsURLKey) ?? fallbackTermsConditionsURL : fallbackTermsConditionsURL
        guard !staticTermsConditionsURL.isEmpty else { return nil }
        if staticTermsConditionsURL.isValidURL {
            return URL(string: staticTermsConditionsURL)
        } else {
            if #available(macOS 13.0, *) {
                let tecURL = URL(filePath: staticTermsConditionsURL, relativeTo: Bundle.main.bundleURL.appending(path: "Contents/Resources/"))
                guard let isReachable = try? tecURL.checkResourceIsReachable(), isReachable else { return nil }
                return tecURL
            } else {
                let tecURL = URL(fileURLWithPath: staticTermsConditionsURL, relativeTo: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/"))
                guard let isReachable = try? tecURL.checkResourceIsReachable(), isReachable else { return nil }
                return tecURL
            }
        }
    }
    static var thirdPartyNoticesURL: URL? {
        let staticThirdPartyNoticesURL = Utils.UserDefaultsHelpers.isDefaultsValueAcceptable(forKey: thirdPartyNoticesKey) ? UserDefaults.standard.string(forKey: thirdPartyNoticesKey) ?? fallbackThirdPartyNoticesURL : fallbackThirdPartyNoticesURL
        guard !staticThirdPartyNoticesURL.isEmpty else { return nil }
        if staticThirdPartyNoticesURL.isValidURL {
            return URL(string: staticThirdPartyNoticesURL)
        } else {
            if #available(macOS 13.0, *) {
                let tpnURL = URL(filePath: staticThirdPartyNoticesURL, relativeTo: Bundle.main.bundleURL.appending(path: "Contents/Resources/"))
                guard let isReachable = try? tpnURL.checkResourceIsReachable(), isReachable else { return nil }
                return tpnURL
            } else {
                let tpnURL = URL(fileURLWithPath: staticThirdPartyNoticesURL, relativeTo: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/"))
                guard let isReachable = try? tpnURL.checkResourceIsReachable(), isReachable else { return nil }
                return tpnURL
            }
        }
    }
    static var shouldRequireTAndCAcceptance: Bool {
        return Utils.UserDefaultsHelpers.managedValue(forKey: shouldRequireTAndCAcceptanceKey, defaultValue: fallbackShouldRequireTAndCAcceptance)
    }
    static var userAcceptedTermsAndConditions: Bool {
        return UserDefaults.standard.bool(forKey: tAndCUserAcceptanceKey)
    }
    static var shouldSkipMigrationSummary: Bool {
        return Utils.UserDefaultsHelpers.managedValue(forKey: skipMigrationSummaryKey, defaultValue: fallbackShouldSkipMigrationSummary)
    }
    static var shouldShowWelcomePageInfo: Bool {
        return Utils.UserDefaultsHelpers.managedValue(forKey: showWelcomePageInfoKey, defaultValue: fallbackShouldShowWelcomePageInfo)
    }
    static var shouldGenerateReport: Bool {
        return Utils.UserDefaultsHelpers.managedValue(forKey: generateReportKey, defaultValue: fallbackShouldGenerateReport)
    }
    
    /// Returns the custom icon source for a given page identifier
    /// - Parameter pageIdentifier: The page identifier (e.g., "welcome", "browser", "setup")
    /// - Returns: The custom icon source string, or nil if not configured
    static func customIconSource(for pageIdentifier: String) -> String? {
        let key: String
        switch pageIdentifier {
        case "welcome":
            key = welcomePageIconKey
        case "browser":
            key = browserPageIconKey
        case "server":
            key = serverPageIconKey
        case "codeVerification":
            key = codeVerificationPageIconKey
        case "setup":
            key = setupPageIconKey
        case "recap":
            key = recapPageIconKey
        case "migration":
            key = migrationPageIconKey
        case "jamfRecon":
            key = jamfReconPageIconKey
        case "reboot":
            key = rebootPageIconKey
        case "final":
            key = finalPageIconKey
        default:
            return nil
        }
        
        guard Utils.UserDefaultsHelpers.isDefaultsValueAcceptable(forKey: key),
              let iconSource = UserDefaults.standard.string(forKey: key),
              !iconSource.isEmpty else {
            return nil
        }
        
        return iconSource
    }
}

// swiftlint:enable file_length
