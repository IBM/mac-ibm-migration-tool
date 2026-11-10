//
//  MigratorFile.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 30/01/2024.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import AppKit
import Combine
import SwiftUI

/// Enumeration to represent different types of files
enum FileType: UInt8, Codable, Hashable, Sendable {
    case directory
    case file
    case symlink
    case app
    case socket
    
    var sortOrder: UInt8 {
        switch self {
        case .directory:
            return 1
        case .file:
            return 3
        case .symlink:
            return 2
        case .app:
            return 3
        case .socket:
            return 4
        }
    }
}

/// Class representing a file in the migration context.
@MainActor
final class MigratorFile {
    
    // MARK: - Published Variables
    
    /// Published property to track if the file is selected
    @Published var isSelected: Bool = false
    /// Published property to track file size
    @Published var fileSize: Int = -1
    /// Published property that track the number of sub-files included in this MigratorFile.
    @Published var numberOfFiles: Int = 0
    
    // MARK: - Variables
    
    /// Type of the file (directory, file, symlink, app)
    nonisolated let type: FileType
    /// URL of the file
    nonisolated let url: MigratorFileURL
    /// True when this file was scanned without the URL exclusion list (explicit app support
    /// paths inside e.g. `~/Library`); children fetched later must be scanned the same way.
    nonisolated let ignoresURLExclusions: Bool
    /// Name of the file
    var name: String
    /// Child files if the file is a directory
    var childFiles: [MigratorFile] = []
    /// True if the file is hidden
    var isHidden: Bool = false
    /// True if the file have already been sent to the connected device.
    var sent: Bool = false
    
    var hLevel: Int = 0
    /// Indicates if this directory is partially migrated/excluded (some subpaths included, some excluded)
    var isPartiallyMigrated: Bool = false
    /// Indicates if this file is synced with a cloud service (iCloud, OneDrive, Box, etc.)
    var isCloudSynced: Bool = false
    
    // MARK: - Intializers
    
    /// Builds a `MigratorFile` (and its retained child tree) from a `FileScanner`-produced
    /// snapshot. Pure object-graph construction - no disk I/O, so it's cheap to run synchronously
    /// on the main actor.
    init(snapshot: MigratorFileSnapshot) {
        self.type = snapshot.type
        self.url = snapshot.url
        self.ignoresURLExclusions = snapshot.ignoresURLExclusions
        self.name = snapshot.name
        self.isHidden = snapshot.isHidden
        self.hLevel = snapshot.hLevel
        self.isPartiallyMigrated = snapshot.isPartiallyMigrated
        self.childFiles = snapshot.children.map { MigratorFile(snapshot: $0) }
    }
    
    /// Asynchronously scans a file URL (off the main actor) and builds a `MigratorFile` from the
    /// result. Replaces the previous synchronous `init?(with:level:excludedItem:excludedChild:)`.
    /// - Parameter url: URL of the source file.
    static func make(with url: URL, level: Int = 0, excludedItem: Bool = false, excludedChild: Bool = false,
                     ignoringURLExclusions: Bool = false) async -> MigratorFile? {
        // This function is main-actor isolated, so calling the (blocking, disk-walking) scan directly
        // would run it on the main thread. Hop to a GCD queue for it, like `AppInfo` does.
        let snapshot: MigratorFileSnapshot? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: FileScanner.scan(url: url, level: level, excludedItem: excludedItem,
                                                                excludedChild: excludedChild,
                                                                ignoringURLExclusions: ignoringURLExclusions))
            }
        }
        guard let snapshot else { return nil }
        return MigratorFile(snapshot: snapshot)
    }
    
    // MARK: - Public Methods

    /// Asynchronously computes and caches the total allocated size (in bytes) and the number of files
    /// contained by the receiver, then publishes the results via `fileSize` and `numberOfFiles`.
    ///
    /// Concurrency and performance: the entire recursive walk (`FileScanner.computeSize`) runs off
    /// the main actor on a plain `Sendable` snapshot of this object's `url`/`type`/`childFiles` -
    /// only building that cheap snapshot and writing the final numbers back touches the main actor,
    /// so a large tree (a whole home folder can be tens of thousands of nodes) doesn't serialize
    /// through it.
    func fetchFileSizeAndCount() async {
        guard self.fileSize == -1 else { return }
        let result = await FileScanner.computeSize(for: FileSizeInput(migratorFile: self))
        self.fileSize = result.size
        self.numberOfFiles = result.count
        if !self.childFiles.isEmpty {
            Self.assign(result.childResults, to: self.childFiles)
        }
    }

    /// Writes each `FileSizeResult` back onto its corresponding retained child, recursing into
    /// grandchildren so every level of the (eagerly-expanded, ≤2-level-deep) retained tree gets its
    /// own `fileSize`/`numberOfFiles` published, matching `files`' order to `results`' order 1:1
    /// (both were built from the same `childFiles` array via `FileSizeInput(migratorFile:)`).
    private static func assign(_ results: [FileSizeResult], to files: [MigratorFile]) {
        for (file, result) in zip(files, results) {
            file.fileSize = result.size
            file.numberOfFiles = result.count
            if !file.childFiles.isEmpty {
                assign(result.childResults, to: file.childFiles)
            }
        }
    }
    
    /// Asynchronously enumerates the immediate children of the directory represented by this
    /// MigratorFile and produces a new array of MigratorFile instances without mutating
    /// `self.childFiles`.
    ///
    /// The scan itself runs on a background task to avoid blocking the main thread; only the
    /// resulting object graph is built on the main actor.
    /// The method is side‑effect free with respect to `self.childFiles` (it does not retain
    /// the computed children on the receiver). It is typically used as a lazy loader for
    /// children during size/count computations (e.g., `fetchFileSizeAndCount()`).
    ///
    /// - Returns: An array of `MigratorFile` representing the immediate children of the directory.
    func fetchUnretainedChilds() async -> [MigratorFile] {
        let snapshots = await FileScanner.scanChildren(of: self.url.fullURL(), ignoringURLExclusions: ignoresURLExclusions)
        return snapshots.map { MigratorFile(snapshot: $0) }
    }
}

// MARK: - FileSizeInput Bridging

extension FileSizeInput {
    /// Builds a cheap (no I/O), main-actor-isolated mirror of a `MigratorFile`'s `url`/`type`/
    /// `childFiles`, so `FileScanner.computeSize(for:)` can then do the actual recursive work
    /// entirely off the main actor.
    @MainActor
    init(migratorFile: MigratorFile) {
        self.init(url: migratorFile.url.fullURL(),
                 type: migratorFile.type,
                 children: migratorFile.childFiles.map { FileSizeInput(migratorFile: $0) },
                 ignoresURLExclusions: migratorFile.ignoresURLExclusions)
    }
}

// MARK: - Equatable, Hashable, Identifiable Conformance

extension MigratorFile: Equatable, Hashable, Identifiable {
    
    // MARK: - Conformance to `Equatable`
    
    nonisolated static func == (lhs: MigratorFile, rhs: MigratorFile) -> Bool {
        return lhs.url == rhs.url
    }
    
    // MARK: - Conformance to `Hashable`
    
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
