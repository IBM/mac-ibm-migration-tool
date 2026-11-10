//
//  RecapViewModel.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 29/01/2024.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import SwiftUI
import Combine

/// ViewModel for the Recap view.
@MainActor
final class RecapViewModel: ObservableObject {

    // MARK: - Observable Variables

    /// Observable object that controls the migration process.
    let migrationController: MigrationController = MigrationController.shared
    
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
    private let logger = MLogger.main.scoped(to: .report)
    /// Indicates whether the recap items have already been loaded during the current lifecycle of the view model.
    private var itemsLoaded: Bool = false
    
    // MARK: - Initializers
    
    /// Initializes the ViewModel with default values and sets up a subscription for available space changes.
    init() {
        self.migrationController.$isConnected.sink { [weak self] newValue in
            self?.connectionInterrupted = !newValue
        }.store(in: &cancellables)
    }

    // MARK: - Public Methods
    
    /// Prepares the recap data by analyzing what will be migrated and what won't
    func prepareRecapData() async {
        self.isLoading = true
        guard let migrationOption = migrationController.migrationOption else {
            logger.log("recapViewModel.prepareRecapData: no migration option selected", type: .fault)
            self.isLoading = false
            return
        }
        guard !itemsLoaded else {
            logger.log("recapViewModel.prepareRecapData: recap items already loaded, skipping")
            self.isLoading = false
            return
        }
        self.itemsExcluded.removeAll()
        await findExcludedItems(migrationOption: migrationOption)
        self.isLoading = false
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
        
        for selectedFile in selectedFiles {
            for exclusionURL in exclusionList where (try? exclusionURL.checkResourceIsReachable()) ?? false {
                let relationship = Utils.FileManagerHelpers.getRelationship(ofItemAt: selectedFile, toItemAt: exclusionURL)
                guard relationship == .containedBy || relationship == .same else { continue }
                if let file = await MigratorFile.make(with: exclusionURL, excludedItem: true) {
                    self.addExcludedFile(file: file)
                }
            }
        }

        self.itemsExcluded.sort { (file1: MigratorFile, file2: MigratorFile) in
            if file1.type != file2.type {
                return file1.type.sortOrder < file2.type.sortOrder
            } else {
                return file1.name < file2.name
            }
        }
        self.itemsLoaded = true
    }
}
