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
class MigrationOption: ObservableObject {
    
    // MARK: - Enums
    
    /// Enum defining different types of migration options.
    enum MigrationOptionType: String, Hashable, Equatable, CaseIterable {
        case lite
        case complete
        case advanced
        case none
        
        /// Computed property returning the name of the migration option.
        var name: String {
            switch self {
            case .lite:
                return "Lite"
            case .complete:
                return "Complete"
            case .advanced:
                return "Advanced"
            case .none:
                return ""
            }
        }
        /// Computed property indicating whether to migrate desktop.
        var migrateDesktop: Bool {
            switch self {
            case .lite:
                return true
            case .complete:
                return false
            case .advanced:
                return false
            case .none:
                return false
            }
        }
        /// Computed property indicating whether to migrate documents.
        var migrateDocuments: Bool {
            return migrateDesktop
        }
        /// Computed property indicating whether to migrate user folder.
        var migrateUserFolder: Bool {
            switch self {
            case .lite:
                return false
            case .complete:
                return true
            case .advanced:
                return false
            case .none:
                return false
            }
        }
        /// Computed property indicating whether to migrate apps.
        var migrateApps: Bool {
            return migrateUserFolder
        }
        /// Computed property indicating whether to migrate preferences.
        var migratePreferences: Bool {
            return migrateUserFolder
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
    /// Published property used to track the number of files inside the migration option.
    @Published var numberOfFiles: Int = 0
    /// Published property to track if architecture detection is in progress.
    @Published var isDetectingArchitectures: Bool = false
    /// Published property to track if architecture detection has completed.
    @Published var architectureDetectionComplete: Bool = false
    
    // MARK: - Variables
    
    /// Unique identifier for the migration option.
    var id: String {
        return type.rawValue
    }
    /// Type of the migration option.
    var type: MigrationOptionType
    /// Name of the migration option.
    var name: String {
        return type.name
    }
    /// List of migration files.
    var migrationFileList: [MigratorFile] = []
    /// List of migration preferences.
    var migrationPreferencesList: [String] = []
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
    
    // MARK: - Private Variables
    
    /// Collection of cancellable subscriptions to manage memory and avoid retain cycles.
    private var cancellables = Set<AnyCancellable>()
    
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
        case .lite:
            if let desktopFolder = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first,
               let desktopFile = MigratorFile(with: desktopFolder) {
                desktopFile.isSelected = true
                self.migrationFileList.append(desktopFile)
            }
            if let documentsFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
               let documentsFile = MigratorFile(with: documentsFolder) {
                documentsFile.isSelected = true
                self.migrationFileList.append(documentsFile)
            }
            self.readyForMigration = true
        case .complete:
            if let userFolderFile = MigratorFile(with: FileManager.default.homeDirectoryForCurrentUser) {
                userFolderFile.isSelected = true
                self.migrationFileList.append(userFolderFile)
            }
            if let applicationsFolder = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first,
               let contentOfApplicationsFolder = try? FileManager.default.contentsOfDirectory(at: applicationsFolder, includingPropertiesForKeys: nil) {
                self.migrationAppList.append(contentsOf: contentOfApplicationsFolder.compactMap({ url in
                    guard let migratorFile = MigratorFile(with: url), migratorFile.type == .app else { return nil }
                    guard let app = DiscoveredApplication(from: migratorFile, architectures: []) else { return nil }
                    app.isSelected = true
                    return app
                }))
            }
            self.readyForMigration = true
        case .advanced:
            if let contentOfHomeDirectory = try? FileManager.default.contentsOfDirectory(at: FileManager.default.homeDirectoryForCurrentUser, includingPropertiesForKeys: nil) {
                self.migrationFileList.append(contentsOf: contentOfHomeDirectory.compactMap({ url in
                    guard let file = MigratorFile(with: url) else { return nil }
                    file.$isSelected.sink { newValue in
                        guard file.isSelected != newValue else { return }
                        Task { @MainActor in
                            self.fileSelectionDidChange(file)
                        }
                    }.store(in: &cancellables)
                    return file
                }))
            }
            if let applicationsFolder = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first,
               let contentOfApplicationsFolder = try? FileManager.default.contentsOfDirectory(at: applicationsFolder, includingPropertiesForKeys: nil) {
                self.migrationAppList.append(contentsOf: contentOfApplicationsFolder.compactMap({ url in
                    guard let migratorFile = MigratorFile(with: url), migratorFile.type == .app else { return nil }
                    guard let app = DiscoveredApplication(from: migratorFile, architectures: []) else { return nil }
                    
                    app.$isSelected.sink { newValue in
                        guard app.isSelected != newValue else { return }
                        Task { @MainActor in
                            self.appSelectionDidChange(app)
                        }
                    }.store(in: &cancellables)
                    return app
                }))
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
    
    /// Asyncronously calculate the size of the migration option.
    func fetchFilesSizeAndCount() async {
        for file in self.migrationFileList {
            await file.fetchFileSizeAndCount()
            if file.isSelected {
                await MainActor.run {
                    self.numberOfFiles += file.numberOfFiles
                    self.size += file.fileSize
                }
            }
        }
        for app in self.migrationAppList {
            await app.migratorFile.fetchFileSizeAndCount()
            if app.isSelected {
                await MainActor.run {
                    self.numberOfFiles += app.migratorFile.numberOfFiles
                    self.size += app.migratorFile.fileSize
                }
            }
        }
        await MainActor.run {
            self.isFinalSize = true
        }
    }
    
    // MARK: - Private Methods
    
    private func fileSelectionDidChange(_ file: MigratorFile) {
        defer {
            evaluateIfReadyForMigration()
        }
        if file.isSelected {
            selectedFiles += 1
            guard file.fileSize != -1 else { return }
            size += file.fileSize
        } else {
            guard selectedFiles > 0 else { return }
            selectedFiles -= 1
            guard file.fileSize != -1 else { return }
            size -= file.fileSize
        }
    }
    
    private func appSelectionDidChange(_ app: DiscoveredApplication) {
        defer {
            evaluateIfReadyForMigration()
        }
        
        if app.isSelected {
            selectedApps += 1
            guard app.migratorFile.fileSize != -1 else { return }
            size += app.migratorFile.fileSize
        } else {
            guard selectedApps > 0 else { return }
            selectedApps -= 1
            guard app.migratorFile.fileSize != -1 else { return }
            size -= app.migratorFile.fileSize
        }
    }
    
    private func evaluateIfReadyForMigration() {
        self.readyForMigration = self.selectedApps > 0 || self.selectedFiles > 0
    }
    
    /// Detects architectures for all applications in migrationAppList
    /// This method can be called on-demand to avoid blocking initial UI load
    func detectAppArchitectures() async {
        // Skip if already detected or in progress
        guard !architectureDetectionComplete && !isDetectingArchitectures else {
            MLogger.main.log("migrationOption.detectAppArchitectures: Skipping - already complete or in progress", type: .debug)
            return
        }
        
        await MainActor.run {
            self.isDetectingArchitectures = true
        }
        
        let detector = ArchitectureDetector.shared
        let totalApps = await MainActor.run { self.migrationAppList.count }
        MLogger.main.log("migrationOption.detectAppArchitectures: Starting detection for \(totalApps) apps", type: .debug)
        
        // Detect architectures sequentially to avoid concurrency issues
        for index in 0..<totalApps {
            let app = await MainActor.run { self.migrationAppList[index] }
            let architectures = detector.detectAppArchitecture(at: app.migratorFile.url.fullURL())
            
            await MainActor.run {
                self.migrationAppList[index].updateArchitectures(architectures)
            }
        }
        
        MLogger.main.log("migrationOption.detectAppArchitectures: Processed \(totalApps) apps", type: .debug)
        
        await MainActor.run {
            self.isDetectingArchitectures = false
            self.architectureDetectionComplete = true
        }
        
        MLogger.main.log("migrationOption.detectAppArchitectures: Detection complete", type: .debug)
    }
}

extension MigrationOption: Identifiable, Hashable {
    
    // MARK: - `Hashable` Protocol Conformance
    
    static func == (lhs: MigrationOption, rhs: MigrationOption) -> Bool {
        return lhs.type == rhs.type
    }
        
    func hash(into hasher: inout Hasher) {
        hasher.combine(type)
    }
}
