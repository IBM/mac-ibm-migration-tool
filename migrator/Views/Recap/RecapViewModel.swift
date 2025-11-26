//
//  RecapViewModel.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 29/01/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import SwiftUI
import Combine

/// ViewModel for the Recap view.
class RecapViewModel: ObservableObject {
    
    // MARK: - Observable Variables
    
    /// Observable object that controls the migration process.
    @ObservedObject var migrationController: MigrationController = MigrationController.shared
    
    // MARK: - Published Variables
    
    /// Tracks if the connection have been interrupted
    @Published var connectionInterrupted: Bool = false
    /// Items that won't be migrated because they're in the exclusion list
    @Published var itemsExcluded: [MigratorFile] = []
    /// Indicates whether the view model is currently performing a background task (e.g., preparing recap data).
    @Published var isLoading: Bool = true
    
    // MARK: - Public Variables
    
    ///
    var duplicateFileMessage: String {
        switch AppContext.duplicateFilesHandlingPolicy {
        case .ignore:
            return "recap.page.ignore.duplicates.label".localized
        case .overwrite:
            return "recap.page.overwrite.duplicates.label".localized
        case .move:
            return String(format: "recap.page.move.duplicates.label".localized, AppContext.relativeBackupPath)
        }
    }
    
    // MARK: - Private Variables
    
    /// Stores any cancellable instances to manage memory and prevent leaks.
    private var cancellables = Set<AnyCancellable>()
    /// Logger instance.
    private let logger: MLogger = MLogger.main
    /// Indicates whether the recap items have already been loaded during the current lifecycle of the view model.
    private var itemsLoaded: Bool = false
    
    // MARK: - Initializers
    
    /// Initializes the ViewModel with default values and sets up a subscription for available space changes.
    init() {
        self.migrationController.$isConnected.sink { newValue in
            Task { @MainActor in
                self.connectionInterrupted = !newValue
            }
        }.store(in: &cancellables)
        
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    // MARK: - Public Methods
    
    /// Prepares the recap data by analyzing what will be migrated and what won't
    func prepareRecapData() async {
        await MainActor.run { self.isLoading = true }
        guard let migrationOption = migrationController.migrationOption, !itemsLoaded else {
            logger.log("recapViewModel.prepareRecapData: No migration option selected", type: .fault)
            await MainActor.run { self.isLoading = false }
            return
        }
        self.itemsExcluded.removeAll()
        await findExcludedItems(migrationOption: migrationOption)
        await MainActor.run { self.isLoading = false }
    }
    
    // MARK: - Private Methods
    
    /// Adds an excluded file to the itemsExcluded list
    private func addExcludedFile(file: MigratorFile) {
        if !itemsExcluded.contains(where: { $0.url.fullURL().path == file.url.fullURL().path }) {
            itemsExcluded.append(file)
        }
    }
    
    /// Finds items that would be migrated but are excluded by urlExclusionList
    private func findExcludedItems(migrationOption: MigrationOption) async {
        let exclusionList = AppContext.urlExclusionList.compactMap { $0 }
        let selectedFiles: [URL] = migrationOption.migrationFileList
            .filter { $0.isSelected }
            .map { $0.url.fullURL() }
        
        await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                for selectedFile in selectedFiles {
                    for exclusionURL in exclusionList where (try? exclusionURL.checkResourceIsReachable()) ?? false {
                        let relationship = Utils.FileManagerHelpers.getRelationship(ofItemAt: selectedFile, toItemAt: exclusionURL)
                        guard relationship == .containedBy || relationship == .same else { continue }
                        if let file = MigratorFile(with: exclusionURL, excludedItem: true) {
                            await MainActor.run { self.addExcludedFile(file: file) }
                        }
                    }
                }
                
                await MainActor.run {
                    self.itemsExcluded.sort { (file1: MigratorFile, file2: MigratorFile) in
                        if file1.type != file2.type {
                            return file1.type.sortOrder < file2.type.sortOrder
                        } else {
                            return file1.name < file2.name
                        }
                    }
                }
                await MainActor.run { self.itemsLoaded = true }
                continuation.resume()
            }
        }
        
    }
}
