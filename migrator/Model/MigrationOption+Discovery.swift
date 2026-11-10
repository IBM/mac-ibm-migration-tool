//
//  MigrationOption+Discovery.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 12/10/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// App support file discovery, preferences discovery, size calculation and architecture
/// detection for a `MigrationOption`. Split out from `MigrationOption.swift` to keep that file
/// under the project's line-length lint limit.
extension MigrationOption {

    /// Discovers support files for all applications in the migration list
    /// - Parameter sensitivity: Search sensitivity level (default: enhanced)
    func discoverAppSupportFiles(sensitivity: AppPathDiscovery.SearchSensitivity = .enhanced) async {
        guard AppContext.shouldMigrateAppSupportFiles else {
            MLogger.main.log("migrationOption.discoverAppSupportFiles: skipping app support file discovery because it is disabled")
            return
        }

        let discovery = AppPathDiscovery()

        MLogger.main.log("migrationOption.discoverAppSupportFiles: starting app support file discovery for \(migrationAppList.count) app(s)")
        
        // Discover support files for each app
        for app in migrationAppList {
            let appInfo = await discovery.discoverPaths(forAppNamed: app.name, at: app.url, sensitivity: sensitivity)
            app.appInfo = appInfo
        }

        MLogger.main.log("migrationOption.discoverAppSupportFiles: completed app support file discovery")
    }

    /// Computes, for each selected app, which of its discovered support paths should actually be
    /// migrated.
    ///
    /// Some vendors (e.g. Microsoft Office) don't use a per-app naming convention for their
    /// support folders, so several apps can independently match the same shared directory (or one
    /// app's match ends up nested inside another app's match). This is computed fresh from only
    /// the apps passed in - rather than mutated once at discovery time - so an unselected app's
    /// match can never "claim" a shared folder away from a selected app that also matched it:
    /// toggling selection can't silently drop another app's data.
    ///
    /// - Parameter selectedApps: The apps currently selected for migration.
    /// - Returns: A mapping from each app to the subset of its discovered support paths to send.
    func deduplicatedSupportPaths(forSelectedApps selectedApps: [DiscoveredApplication]) -> [DiscoveredApplication: Set<URL>] {
        struct Entry {
            let app: DiscoveredApplication
            let path: URL
        }

        var entries: [Entry] = []
        for app in selectedApps {
            guard let appInfo = app.appInfo else { continue }
            for path in appInfo.allDiscoveredPaths {
                entries.append(Entry(app: app, path: path))
            }
        }

        entries.sort { $0.path.standardizedFileURL.pathComponents.count < $1.path.standardizedFileURL.pathComponents.count }

        var claimedPaths: [URL] = []
        var result: [DiscoveredApplication: Set<URL>] = [:]
        for entry in entries {
            let isAlreadyClaimed = claimedPaths.contains { claimed in
                let relationship = Utils.FileManagerHelpers.getRelationship(ofItemAt: entry.path, toItemAt: claimed)
                return relationship == .same || relationship == .containedBy
            }

            guard !isAlreadyClaimed else {
                MLogger.main.log("migrationOption.deduplicatedSupportPaths: dropping duplicate support path \"\(entry.path.path)\", already covered by another selected app's support files")
                continue
            }

            claimedPaths.append(entry.path)
            result[entry.app, default: []].insert(entry.path)
        }

        return result
    }
    
    /// Removes from `size` and `numberOfFiles` the support files that are counted for more than one
    /// selected app but sent only once (see `deduplicatedSupportPaths(forSelectedApps:)`).
    ///
    /// The totals add up every app's discovered support paths on their own, so a folder shared by
    /// several apps (e.g. Microsoft Office's group containers) is counted once per app, while the
    /// migration sends it a single time. Without this the progress never reaches 100%, the
    /// time left is overestimated, and the destination and the report are told a size that is too big.
    /// Call it once the selection is final, right before the migration starts. Paths whose size is
    /// no longer in `FileSizeCache` (entries expire after an hour) can't be discounted.
    func discountDuplicatedSupportPaths() {
        guard AppContext.shouldMigrateAppSupportFiles, !hasDiscountedDuplicatedSupportPaths else { return }
        hasDiscountedDuplicatedSupportPaths = true

        let selectedApps = migrationAppList.filter { $0.isSelected }
        let pathsToSend = deduplicatedSupportPaths(forSelectedApps: selectedApps)
        var duplicatedSize = 0
        var duplicatedFiles = 0
        for app in selectedApps {
            guard let appInfo = app.appInfo else { continue }
            let sentPaths = pathsToSend[app] ?? []
            for path in appInfo.allDiscoveredPaths where !sentPaths.contains(path) {
                guard let cached = FileSizeCache.shared.getCachedSize(for: path) else {
                    MLogger.main.log("migrationOption.discountDuplicatedSupportPaths: size of \"\(path.path)\" is no longer cached, it can't be discounted", type: .default)
                    continue
                }
                duplicatedSize += cached.size
                duplicatedFiles += cached.numberOfFiles
            }
        }

        size = max(0, size - duplicatedSize)
        numberOfFiles = max(0, numberOfFiles - duplicatedFiles)
        let discountedSize = ByteCountFormatter.string(fromByteCount: Int64(duplicatedSize), countStyle: .file)
        MLogger.main.log("migrationOption.discountDuplicatedSupportPaths: discounted \(duplicatedFiles) file(s), \(discountedSize) of support files shared between apps", type: .default)
    }

    /// Discovers available macOS preference groups and populates `migrationPreferencesList`.
    /// For `.standard` presets with the `.preferences` category enabled, every discovered group is
    /// pre-selected. For `.advanced`, groups are discovered unselected and subscribed to so the user
    /// can choose which ones to migrate.
    func discoverPreferences() async {
        guard AppContext.shouldMigratePreferences else {
            MLogger.main.log("migrationOption.discoverPreferences: skipping preferences discovery because it is disabled")
            return
        }
        let groups = await PreferencesDiscovery.discoverAvailableGroups().sorted { $0.name < $1.name }
        switch self.type {
        case .standard(let preset) where preset.categories.contains(.preferences):
            groups.forEach { $0.isSelected = true }
            self.migrationPreferencesList = groups
        case .advanced:
            groups.forEach { group in
                group.$isSelected.sink { newValue in
                    guard group.isSelected != newValue else { return }
                    Task { @MainActor in
                        self.preferenceSelectionDidChange(group)
                    }
                }.store(in: &self.cancellables)
            }
            self.migrationPreferencesList = groups
        case .standard, .none:
            break
        }
    }

    /// Asyncronously calculate the size of the migration option.
    ///
    /// Publishes the running `size`/`numberOfFiles` totals in batches of `aggregateUpdateBatchSize`
    /// rather than once per item: `MigrationSetupViewModel` observes `$size` to drive a live
    /// "calculating..." label while this runs, so totals still need to tick up progressively -
    /// batching just reduces how many SwiftUI-triggering writes that requires for large app/file
    /// lists. Per-item UI (each file's own `fileSize`, each app's `objectWillChange`) is published
    /// immediately as before; only the aggregate total's update cadence changes.
    func fetchFilesSizeAndCount() async {
        let aggregateUpdateBatchSize = 10
        var pendingFiles = 0
        var pendingSize = 0

        for (index, file) in self.migrationFileList.enumerated() {
            await file.fetchFileSizeAndCount()
            if file.isSelected {
                pendingFiles += file.numberOfFiles
                pendingSize += file.fileSize
            }
            if (index + 1).isMultiple(of: aggregateUpdateBatchSize) {
                self.numberOfFiles += pendingFiles
                self.size += pendingSize
                pendingFiles = 0
                pendingSize = 0
            }
        }
        if pendingFiles != 0 || pendingSize != 0 {
            self.numberOfFiles += pendingFiles
            self.size += pendingSize
            pendingFiles = 0
            pendingSize = 0
        }

        for (index, app) in self.migrationAppList.enumerated() {
            await app.migratorFile.fetchFileSizeAndCount()
            let supportSize = AppContext.shouldMigrateAppSupportFiles ? await app.appInfo?.getTotalSize() ?? 0 : 0
            let supportFileCount = AppContext.shouldMigrateAppSupportFiles ? await app.appInfo?.getTotalFileCount() ?? 0 : 0
            if app.isSelected {
                pendingFiles += app.migratorFile.numberOfFiles + supportFileCount
                pendingSize += app.migratorFile.fileSize + supportSize
            }
            app.objectWillChange.send()
            if (index + 1).isMultiple(of: aggregateUpdateBatchSize) {
                self.numberOfFiles += pendingFiles
                self.size += pendingSize
                pendingFiles = 0
                pendingSize = 0
            }
        }
        if pendingFiles != 0 || pendingSize != 0 {
            self.numberOfFiles += pendingFiles
            self.size += pendingSize
        }

        for group in self.migrationPreferencesList where group.isSelected {
            self.size += group.payloadSize
        }
        self.isFinalSize = true
    }
    
    /// Detects architectures for all applications in migrationAppList
    /// This method can be called on-demand to avoid blocking initial UI load
    func detectAppArchitectures() async {
        // Skip if already detected or in progress
        guard !architectureDetectionComplete && !isDetectingArchitectures else {
            MLogger.main.log("migrationOption.detectAppArchitectures: skipping, already complete or in progress")
            return
        }

        self.isDetectingArchitectures = true

        let detector = ArchitectureDetector.shared
        let totalApps = self.migrationAppList.count
        MLogger.main.log("migrationOption.detectAppArchitectures: starting detection for \(totalApps) app(s)")

        // Detect architectures sequentially to avoid concurrency issues
        for index in 0..<totalApps {
            let app = self.migrationAppList[index]
            let architectures = await detector.detectAppArchitecture(at: app.migratorFile.url.fullURL())
            self.migrationAppList[index].updateArchitectures(architectures)
        }

        MLogger.main.log("migrationOption.detectAppArchitectures: processed \(totalApps) app(s)")

        self.isDetectingArchitectures = false
        self.architectureDetectionComplete = true

        MLogger.main.log("migrationOption.detectAppArchitectures: detection complete")
    }
}
