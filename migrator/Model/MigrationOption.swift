//
//  MigrationOption.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 31/01/2024.
//  © Copyright IBM Corp. 2023, 2024
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
    /// List of migration apps.
    var migrationAppList: [MigratorFile] = []
    
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
            if let desktopFolder = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
                let desktopFile = MigratorFile(with: desktopFolder)
                desktopFile.isSelected = true
                self.migrationFileList.append(desktopFile)
            }
            if let documentsFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let documentsFile = MigratorFile(with: documentsFolder)
                documentsFile.isSelected = true
                self.migrationFileList.append(documentsFile)
            }
            self.readyForMigration = true
        case .complete:
            let userFolderFile = MigratorFile(with: FileManager.default.homeDirectoryForCurrentUser)
            userFolderFile.isSelected = true
            self.migrationFileList.append(userFolderFile)
            if let applicationsFolder = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first {
                let applicationFolderFile = MigratorFile(with: applicationsFolder)
                applicationFolderFile.isSelected = true
                self.migrationFileList.append(applicationFolderFile)
            }
            self.readyForMigration = true
        case .advanced:
            if let contentOfHomeDirectory = try? FileManager.default.contentsOfDirectory(at: FileManager.default.homeDirectoryForCurrentUser, includingPropertiesForKeys: nil) {
                self.migrationFileList.append(contentsOf: contentOfHomeDirectory.filter({ url in
                    return (!AppContext.urlExclusionList.contains(url) && !AppContext.excludedFileExtensions.contains(url.lastPathComponent) && url.lastPathComponent.first != "~") || AppContext.explicitAllowList.contains(where: { $0?.absoluteString.contains(url.absoluteString) ?? false })
                }).compactMap({ url in
                    let file = MigratorFile(with: url, allowListed: AppContext.explicitAllowList.contains(where: { $0?.absoluteString.contains(url.absoluteString) ?? false }))
                    file.$isSelected.sink { newValue in
                        guard file.isSelected != newValue else { return }
                        Task { @MainActor in
                            self.fileSelectionDidChange(file)
                        }
                    }.store(in: &cancellables)
                    return file.type != .socket ? file : nil
                }))
            }
            if let applicationsFolder = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first,
               let contentOfApplicationsFolder = try? FileManager.default.contentsOfDirectory(at: applicationsFolder, includingPropertiesForKeys: nil) {
                self.migrationAppList.append(contentsOf: contentOfApplicationsFolder.filter({ url in
                    return !AppContext.urlExclusionList.contains(url) && !AppContext.excludedFileExtensions.contains(url.lastPathComponent) && url.lastPathComponent.first != "~"
                }).map({ url in
                    let appFile = MigratorFile(with: url)
                    appFile.$isSelected.sink { newValue in
                        guard appFile.isSelected != newValue else { return }
                        Task { @MainActor in
                            self.appSelectionDidChange(appFile)
                        }
                    }.store(in: &cancellables)
                    return appFile
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
        self.migrationAppList.removeAll(where: { $0.type != .app })
        self.migrationAppList.sort { (file1: MigratorFile, file2: MigratorFile) in
            if file1.type != file2.type {
                return file1.type.sortOrder < file2.type.sortOrder
            } else {
                return file1.name < file2.name
            }
        }
    }
    // swiftlint:enable function_body_length
    
    /// Asyncronously calculate the size of the migration option.
    func fetchFilesSizeAndCount() async {
        for file in self.migrationFileList {
            await file.fetchFilesSizeAndCount()
            if file.isSelected {
                await MainActor.run {
                    self.numberOfFiles += file.numberOfFiles
                    self.size += file.fileSize
                }
            }
        }
        for app in self.migrationAppList {
            await app.fetchFilesSizeAndCount()
            if app.isSelected {
                await MainActor.run {
                    self.numberOfFiles += app.numberOfFiles
                    self.size += app.fileSize
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
    
    private func appSelectionDidChange(_ app: MigratorFile) {
        defer {
            evaluateIfReadyForMigration()
        }
        if app.isSelected {
            selectedApps += 1
            guard app.fileSize != -1 else { return }
            size += app.fileSize
        } else {
            guard selectedApps > 0 else { return }
            selectedApps -= 1
            guard app.fileSize != -1 else { return }
            size -= app.fileSize
        }
    }
    
    private func evaluateIfReadyForMigration() {
        self.readyForMigration = self.selectedApps > 0 || self.selectedFiles > 0
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
