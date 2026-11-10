//
//  MigrationOption.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 31/01/2024.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import SwiftUI
import Combine

/// Class representing a migration option, conforming to Identifiable and Hashable protocols.
@MainActor
final class MigrationOption: ObservableObject {
    
    // MARK: - Enums
    
    /// Enum defining different types of migration options.
    ///
    /// `.standard` wraps a `MigrationPreset`, the data-driven replacement for the historical
    /// hardcoded `Lite`/`Complete` cases. An admin-defined list of presets (see
    /// `AppContext.migrationPresets`) can replace `Lite`/`Complete` entirely without any code change.
    enum MigrationOptionType: Hashable, Sendable {
        case standard(MigrationPreset)
        case advanced
        case none

        /// Stable identifier for the option: the preset's `id` for `.standard`, otherwise a fixed
        /// string. Used for `MigrationOption.id` and recorded in the migration report.
        var identifier: String {
            switch self {
            case .standard(let preset):
                return preset.id
            case .advanced:
                return "advanced"
            case .none:
                return "none"
            }
        }
        /// Computed property returning the name of the migration option.
        var name: String {
            switch self {
            case .standard(let preset):
                return preset.name
            case .advanced:
                return "Advanced"
            case .none:
                return ""
            }
        }
    }
    
    // MARK: - Published Variables
    
    /// Published property to track the size of the migration option.
    @Published var size: Int = 0
    /// Published property to track the conclusion of the file size calculation.
    @Published var isFinalSize: Bool = false
    /// Published property to track if the selected option is ready to start the migration.
    @Published var readyForMigration: Bool = false
    /// Published property used as counter for the number of selected files.
    @Published var selectedFiles: Int = 0
    /// Published property used as counter for the number of selected apps.
    @Published var selectedApps: Int = 0
    /// Published property used as counter for the number of selected preference groups.
    @Published var selectedPreferences: Int = 0
    /// Published property used to track the number of files inside the migration option.
    @Published var numberOfFiles: Int = 0
    /// True once `discountDuplicatedSupportPaths()` has corrected `size` and `numberOfFiles`.
    var hasDiscountedDuplicatedSupportPaths: Bool = false
    /// Published property to track if architecture detection is in progress.
    @Published var isDetectingArchitectures: Bool = false
    /// Published property to track if architecture detection has completed.
    @Published var architectureDetectionComplete: Bool = false
    
    // MARK: - Variables
    
    /// Unique identifier for the migration option.
    nonisolated var id: String {
        return type.identifier
    }
    /// Type of the migration option.
    nonisolated let type: MigrationOptionType
    /// Name of the migration option.
    var name: String {
        return type.name
    }
    /// List of migration files.
    var migrationFileList: [MigratorFile] = []
    /// List of migration preferences.
    var migrationPreferencesList: [PreferenceGroup] = []
    /// List of applications to migrate with architecture information.
    var migrationAppList: [DiscoveredApplication] = []
    
    // MARK: - Computed Properties
    
    /// Returns all Intel-only applications
    var intelOnlyApps: [DiscoveredApplication] {
        return migrationAppList.filter { $0.architectureType == .intelOnly }
    }
    
    /// Returns all Universal applications
    var universalApps: [DiscoveredApplication] {
        return migrationAppList.filter { $0.architectureType == .universal }
    }
    
    /// Returns all Apple Silicon-only applications
    var appleSiliconOnlyApps: [DiscoveredApplication] {
        return migrationAppList.filter { $0.architectureType == .appleSiliconOnly }
    }
    
    // MARK: - Internal Variables
    
    /// Collection of cancellable subscriptions to manage memory and avoid retain cycles.
    var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initializers
    
    /// Initialize a new instance from a defined `MigrationOptionType`.
    init(type: MigrationOptionType) {
        self.type = type
    }

    // MARK: - Public Methods
    
    // swiftlint:disable function_body_length
    /// Asyncronously migration option files.
    func loadFiles() async {
        switch type {
        case .standard(let preset):
            // Tracks paths already added so a shared/nested location (e.g. an `additionalPaths`
            // entry under Desktop, or the whole home folder covering everything else) is never
            // migrated twice.
            var addedPaths: [URL] = []
            func addFileIfNeeded(at url: URL) async {
                let isAlreadyCovered = addedPaths.contains { existing in
                    let relationship = Utils.FileManagerHelpers.getRelationship(ofItemAt: url, toItemAt: existing)
                    return relationship == .same || relationship == .containedBy
                }
                guard !isAlreadyCovered else {
                    MLogger.main.log("migrationOption.loadFiles: skipping \"\(url.path)\", already covered by another path in preset \"\(preset.id)\"")
                    return
                }
                guard let file = await MigratorFile.make(with: url) else { return }
                file.isSelected = true
                self.migrationFileList.append(file)
                addedPaths.append(url)
            }

            if preset.categories.contains(.userFolder) {
                // The whole home folder already covers Desktop, Documents and any `additionalPaths`.
                await addFileIfNeeded(at: FileManager.default.homeDirectoryForCurrentUser)
            } else {
                // Exhaustive over `MigrationPreset.Category`: adding a new path-based standard
                // category only means adding a case here (and to the enum) - the preset's shape
                // and its decoding stay the same.
                for category in MigrationPreset.Category.allCases where preset.categories.contains(category) {
                    switch category {
                    case .desktop:
                        if let desktopFolder = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
                            await addFileIfNeeded(at: desktopFolder)
                        }
                    case .documents:
                        if let documentsFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                            await addFileIfNeeded(at: documentsFolder)
                        }
                    case .userFolder:
                        break // Handled above.
                    case .apps, .preferences:
                        break // `.apps` is handled below; `.preferences` in `discoverPreferences()`.
                    }
                }
                for pathString in preset.additionalPaths {
                    guard let url = Utils.Customization.parseProfileURL(pathString) else {
                        MLogger.main.log("migrationOption.loadFiles: could not parse additional path \"\(pathString)\" for preset \"\(preset.id)\"")
                        continue
                    }
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        MLogger.main.log("migrationOption.loadFiles: skipping non-existent additional path \"\(url.path)\" for preset \"\(preset.id)\"")
                        continue
                    }
                    await addFileIfNeeded(at: url)
                }
            }

            if preset.categories.contains(.apps) {
                if AppContext.shouldExcludeApplicationsFolder {
                    MLogger.main.log("migrationOption.loadFiles: skipping Applications folder for preset \"\(preset.id)\" because excludeApplicationsFolder is enabled")
                } else if let applicationsFolder = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first {
                    do {
                        let contentOfApplicationsFolder = try FileManager.default.contentsOfDirectory(at: applicationsFolder, includingPropertiesForKeys: nil)
                        for url in contentOfApplicationsFolder {
                            guard let migratorFile = await MigratorFile.make(with: url), migratorFile.type == .app else { continue }
                            guard let app = DiscoveredApplication(from: migratorFile, architectures: []) else { continue }
                            app.isSelected = true
                            self.migrationAppList.append(app)
                        }
                    } catch {
                        MLogger.main.log("migrationOption.loadFiles: failed to list \"\(applicationsFolder.path)\" for preset \"\(preset.id)\": \(error.localizedDescription)", type: .error)
                    }
                } else {
                    MLogger.main.log("migrationOption.loadFiles: could not resolve the Applications folder URL for preset \"\(preset.id)\"", type: .error)
                }
            }

            self.readyForMigration = !self.migrationFileList.isEmpty || !self.migrationAppList.isEmpty || preset.categories.contains(.preferences)
        case .advanced:
            if let contentOfHomeDirectory = try? FileManager.default.contentsOfDirectory(at: FileManager.default.homeDirectoryForCurrentUser, includingPropertiesForKeys: nil) {
                for url in contentOfHomeDirectory {
                    guard let file = await MigratorFile.make(with: url) else { continue }
                    file.$isSelected.sink { newValue in
                        guard file.isSelected != newValue else { return }
                        Task { @MainActor in
                            self.fileSelectionDidChange(file)
                        }
                    }.store(in: &cancellables)
                    self.migrationFileList.append(file)
                }
            }
            if AppContext.shouldExcludeApplicationsFolder {
                MLogger.main.log("migrationOption.loadFiles: skipping Applications folder for advanced option because excludeApplicationsFolder is enabled")
            } else if let applicationsFolder = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first {
                do {
                    let contentOfApplicationsFolder = try FileManager.default.contentsOfDirectory(at: applicationsFolder, includingPropertiesForKeys: nil)
                    for url in contentOfApplicationsFolder {
                        guard let migratorFile = await MigratorFile.make(with: url), migratorFile.type == .app else { continue }
                        guard let app = DiscoveredApplication(from: migratorFile, architectures: []) else { continue }

                        app.$isSelected.sink { newValue in
                            guard app.isSelected != newValue else { return }
                            Task { @MainActor in
                                self.appSelectionDidChange(app)
                            }
                        }.store(in: &cancellables)
                        self.migrationAppList.append(app)
                    }
                } catch {
                    MLogger.main.log("migrationOption.loadFiles: failed to list \"\(applicationsFolder.path)\" for advanced option: \(error.localizedDescription)", type: .error)
                }
            } else {
                MLogger.main.log("migrationOption.loadFiles: could not resolve the Applications folder URL for advanced option", type: .error)
            }
        case .none:
            break
        }
        self.migrationFileList.sort { (file1: MigratorFile, file2: MigratorFile) in
            if file1.type != file2.type {
                return file1.type.sortOrder < file2.type.sortOrder
            } else {
                return file1.name < file2.name
            }
        }
        self.migrationAppList.sort { (app1: DiscoveredApplication, app2: DiscoveredApplication) in
            return app1.name < app2.name
        }
    }
    // swiftlint:enable function_body_length

    // MARK: - Internal Methods

    func fileSelectionDidChange(_ file: MigratorFile) {
        defer {
            evaluateIfReadyForMigration()
        }
        if file.isSelected {
            selectedFiles += 1
            guard file.fileSize != -1 else { return }
            size += file.fileSize
            numberOfFiles += file.numberOfFiles
        } else {
            guard selectedFiles > 0 else { return }
            selectedFiles -= 1
            guard file.fileSize != -1 else { return }
            size -= file.fileSize
            numberOfFiles = max(0, numberOfFiles - file.numberOfFiles)
        }
    }
    
    func appSelectionDidChange(_ app: DiscoveredApplication) {
        defer {
            evaluateIfReadyForMigration()
        }
        
        if app.isSelected {
            selectedApps += 1
            guard let appSize = calculatedSize(for: app) else { return }
            size += appSize
            numberOfFiles += calculatedFileCount(for: app)
        } else {
            guard selectedApps > 0 else { return }
            selectedApps -= 1
            guard let appSize = calculatedSize(for: app) else { return }
            size -= appSize
            numberOfFiles = max(0, numberOfFiles - calculatedFileCount(for: app))
        }
    }
    
    func calculatedSize(for app: DiscoveredApplication) -> Int? {
        guard app.migratorFile.fileSize != -1 else { return nil }
        let supportSize = AppContext.shouldMigrateAppSupportFiles ? app.appInfo?.cachedTotalSize ?? 0 : 0
        return app.migratorFile.fileSize + supportSize
    }

    /// Number of files `app` contributes to `numberOfFiles`, mirroring `calculatedSize(for:)`.
    /// Only meaningful once `calculatedSize(for:)` is non-nil (the app has been sized).
    func calculatedFileCount(for app: DiscoveredApplication) -> Int {
        let supportCount = AppContext.shouldMigrateAppSupportFiles ? app.appInfo?.cachedTotalFileCount ?? 0 : 0
        return app.migratorFile.numberOfFiles + supportCount
    }

    func preferenceSelectionDidChange(_ group: PreferenceGroup) {
        defer {
            evaluateIfReadyForMigration()
        }
        if group.isSelected {
            selectedPreferences += 1
            size += group.payloadSize
        } else {
            guard selectedPreferences > 0 else { return }
            selectedPreferences -= 1
            size -= group.payloadSize
        }
    }

    func evaluateIfReadyForMigration() {
        self.readyForMigration = self.selectedApps > 0 || self.selectedFiles > 0 || self.selectedPreferences > 0
    }
}

extension MigrationOption: Identifiable, Hashable {
    
    // MARK: - `Hashable` Protocol Conformance
    
    nonisolated static func == (lhs: MigrationOption, rhs: MigrationOption) -> Bool {
        return lhs.type == rhs.type
    }
        
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(type)
    }
}
