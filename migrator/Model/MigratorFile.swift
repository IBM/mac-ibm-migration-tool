//
//  MigratorFile.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 30/01/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import AppKit
import Combine
import SwiftUI

/// Enumeration to represent different types of files
enum FileType: UInt8, Codable, Hashable {
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
class MigratorFile {
    
    // MARK: - Published Variables
    
    /// Published property to track if the file is selected
    @Published var isSelected: Bool = false
    /// Published property to track file size
    @Published var fileSize: Int = -1
    /// Published property that track the number of sub-files included in this MigratorFile.
    @Published var numberOfFiles: Int = 0
    
    // MARK: - Variables
    
    /// Type of the file (directory, file, symlink, app)
    var type: FileType
    /// URL of the file
    var url: MigratorFileURL
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
    
    // swiftlint:disable function_body_length
    /// Asynchronous initialization to fetch file attributes and child files from a file URL.
    /// - Parameter url: URL of the source file.
    init?(with url: URL, level: Int = 0, excludedItem: Bool = false, excludedChild: Bool = false) {
        var shouldContinue: Bool
        if excludedItem {
            shouldContinue = true
        } else if excludedChild {
            shouldContinue = Utils.FileManagerHelpers.shouldIgnorePath(url)
        } else {
            shouldContinue = !Utils.FileManagerHelpers.shouldIgnorePath(url)
        }
        guard shouldContinue else { return nil }
        self.name = url.lastPathComponent
        self.url = MigratorFileURL(with: url)
        self.hLevel = level
        self.isHidden = url.lastPathComponent.hasPrefix(".")
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.relativePath) as NSDictionary {
            let filetype = FileAttributeType(rawValue: attributes.fileType() ?? "")
            switch filetype {
            case .typeDirectory:
                guard url.pathExtension != "app" else {
                    self.type = .app
                    break
                }
                self.type = .directory
                guard hLevel <= 2 else { break }
                if let childsURL = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) {
                    var partial = false
                    for childURL in childsURL {
                        if (try? childURL.checkResourceIsReachable()) == false {
                            MLogger.main.log("migratorFile.init: Skipping unreachable file: \(childURL.relativePath)", type: .fault)
                            continue
                        }
                        if let childFile = MigratorFile(with: childURL, level: hLevel+1, excludedChild: excludedItem) {
                            self.childFiles.append(childFile)
                        } else {
                            partial = true
                        }
                    }
                    if !self.childFiles.isEmpty && partial {
                        self.isPartiallyMigrated = true
                    }
                }
            case .typeRegular:
                self.type = .file
            case .typeSymbolicLink:
                self.type = .symlink
            case .typeSocket:
                MLogger.main.log("migratorFile.init: Socket file detected: \(url.relativePath)", type: .debug)
                return nil
            case .typeBlockSpecial, .typeCharacterSpecial, .typeUnknown:
                MLogger.main.log("migratorFile.init: Special file type detected: \(filetype.rawValue) at \(url.relativePath)", type: .default)
                self.type = .file
            default:
                self.type = .file
            }
        } else {
            MLogger.main.log("migratorFile.init: Could not get attributes for file: \(url.relativePath)", type: .fault)
            self.type = .file
        }
        self.childFiles.sort { (file1: MigratorFile, file2: MigratorFile) in
            if file1.type != file2.type {
                return file1.type.sortOrder < file2.type.sortOrder
            } else {
                return file1.name < file2.name
            }
        }
    }
    // swiftlint:enable function_body_length
    
    // MARK: - Public Methods

    /// Asynchronously computes and caches the total allocated size (in bytes) and the number of files
    /// contained by the receiver, then publishes the results via `fileSize` and `numberOfFiles`.
    ///
    /// Concurrency and performance:
    /// - Work is performed on a detached task with `.utility` priority to avoid blocking the main thread.
    /// - Child processing is batched (size 10) and executed in a `TaskGroup` to cap concurrency.
    /// - Published properties are updated in one hop on the main actor.
    func fetchFileSizeAndCount() async {
        guard self.fileSize == -1 else { return }
        
        // Use a task to avoid blocking the main thread
        await Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            var size = 0
            var count = 0
            
            switch self.type {
            case .app:
                if let appSize = try? await self.url.fullURL().directoryTotalAllocatedSize() {
                    size = appSize
                }
                if let filesCount = try? await self.url.fullURL().directoryTotalNumberOfFiles() {
                    count = filesCount + 1
                }
            case .socket:
                break
            case .directory:
                let availableChildFiles = self.childFiles.isEmpty ? await self.fetchUnretainedChilds() : self.childFiles
                let tempSize = (try? self.url.fullURL().resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0) ?? 0
                
                await withTaskGroup(of: (Int, Int).self, returning: Void.self) { group in
                    let batchSize = 10
                    let batches = stride(from: 0, to: availableChildFiles.count, by: batchSize)
                        .map { Array(availableChildFiles[$0..<min($0 + batchSize, availableChildFiles.count)]) }
                    for batch in batches {
                        for file in batch {
                            group.addTask(priority: .utility) {
                                await file.fetchFileSizeAndCount()
                                return (file.fileSize, file.numberOfFiles)
                            }
                        }
                        for await result in group {
                            size += result.0
                            count += result.1
                        }
                    }
                }
                size += tempSize
                count += 1
            default:
                size = (try? self.url.fullURL().resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0) ?? 0
                count = 1
            }
            await MainActor.run { [size, count] in
                self.fileSize = size
                self.numberOfFiles = count
            }
        }.value
    }
    
    /// Asynchronously enumerates the immediate children of the directory represented by this
    /// MigratorFile and produces a new array of MigratorFile instances without mutating
    /// `self.childFiles`.
    ///
    /// The work is executed on a detached task with `.utility` priority to avoid blocking the
    /// main thread.
    /// The method is side‑effect free with respect to `self.childFiles` (it does not retain
    /// the computed children on the receiver). It is typically used as a lazy loader for
    /// children during size/count computations (e.g., `fetchFileSizeAndCount()`).
    ///
    /// - Returns: An array of `MigratorFile` representing the immediate children of the directory.
    func fetchUnretainedChilds() async -> [MigratorFile] {
        return await Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return [] }
            guard let childURLs = try? FileManager.default.contentsOfDirectory(
                at: self.url.fullURL(),
                includingPropertiesForKeys: [.totalFileAllocatedSizeKey]
            ) else { return [] }
            
            // Process URLs in batches to avoid overwhelming the system
            let batchSize = 20
            var tempChilds: [MigratorFile] = []
            tempChilds.reserveCapacity(childURLs.count)
            await withTaskGroup(of: [MigratorFile].self) { group in
                for batch in stride(from: 0,
                                    to: childURLs.count,
                                    by: batchSize).map({ Array(childURLs[$0..<min($0 + batchSize, childURLs.count)]) }) {
                    group.addTask(priority: .utility) {
                        var batchResults: [MigratorFile] = []
                        batchResults.reserveCapacity(batch.count)
                        
                        for childURL in batch {
                            guard (try? childURL.checkResourceIsReachable()) != false else {
                                MLogger.main.log("migratorFile.fetchUnretainedChilds: File not reachable: \(childURL.relativePath)", type: .fault)
                                continue
                            }
                            if let childFile = MigratorFile(with: childURL) {
                                batchResults.append(childFile)
                            }
                        }
                        return batchResults
                    }
                }
                for await batchResults in group {
                    tempChilds.append(contentsOf: batchResults)
                }
            }
            tempChilds.sort { (file1: MigratorFile, file2: MigratorFile) in
                if file1.type != file2.type {
                    return file1.type.sortOrder < file2.type.sortOrder
                } else {
                    return file1.name < file2.name
                }
            }
            return tempChilds
        }.value
    }
}

extension MigratorFile: Equatable, Hashable, Identifiable {
    
    // MARK: - Conformance to `Equatable`
    
    static func == (lhs: MigratorFile, rhs: MigratorFile) -> Bool {
        return lhs.url == rhs.url
    }
    
    // MARK: - Conformance to `Hashable`
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
