//
//  FileScanner.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 12/10/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// Nonisolated, off-main snapshot of a file on disk. `FileScanner` produces these by walking the
/// file system in the background; `MigratorFile` (main-actor-isolated) turns them into its live,
/// `@Published`-backed object graph without doing any disk I/O itself.
struct MigratorFileSnapshot: Sendable {
    let type: FileType
    let url: MigratorFileURL
    let name: String
    let isHidden: Bool
    let hLevel: Int
    let isPartiallyMigrated: Bool
    /// True when this node (and its descendants) were scanned without the URL exclusion list.
    let ignoresURLExclusions: Bool
    let children: [MigratorFileSnapshot]
}

/// Namespace for the file-system scanning work that used to live directly on `MigratorFile`.
/// Everything here is `nonisolated` and operates only on `Sendable` values (URLs, snapshots), so
/// it can run freely on background tasks without crossing into main-actor-isolated state.
enum FileScanner {

    /// Scans a URL (and, for directories up to 2 levels deep, its children) into a snapshot.
    /// Mirrors the previous `MigratorFile.init?(with:level:excludedItem:excludedChild:)`.
    /// - Parameter ignoringURLExclusions: Scan this tree without applying the URL exclusion list
    ///   (see `Utils.FileManagerHelpers.shouldIgnorePath`). Propagates to every descendant.
    static func scan(url: URL, level: Int = 0, excludedItem: Bool = false, excludedChild: Bool = false,
                     ignoringURLExclusions: Bool = false) -> MigratorFileSnapshot? {
        let shouldContinue: Bool
        if excludedItem {
            shouldContinue = true
        } else if excludedChild {
            shouldContinue = Utils.FileManagerHelpers.shouldIgnorePath(url, ignoringURLExclusions: ignoringURLExclusions)
        } else {
            shouldContinue = !Utils.FileManagerHelpers.shouldIgnorePath(url, ignoringURLExclusions: ignoringURLExclusions)
        }
        guard shouldContinue else { return nil }

        let name = url.lastPathComponent
        let trackedURL = MigratorFileURL(with: url)
        let isHidden = name.hasPrefix(".")
        var type: FileType
        var children: [MigratorFileSnapshot] = []
        var isPartiallyMigrated = false

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.relativePath) as NSDictionary
            let filetype = FileAttributeType(rawValue: attributes.fileType() ?? "")
            switch filetype {
            case .typeDirectory:
                if url.pathExtension == "app" {
                    type = .app
                } else {
                    type = .directory
                    if level <= 2 {
                        if let childsURL = try? FileManager.default.contentsOfDirectory(at: url,
                                                                                        includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) {
                            var partial = false
                            for childURL in childsURL {
                                if (try? childURL.checkResourceIsReachable()) == false {
                                    MLogger.main.log("fileScanner.scan: skipping unreachable file - \(childURL.relativePath)", type: .fault)
                                    continue
                                }
                                if let childSnapshot = scan(url: childURL, level: level + 1, excludedChild: excludedItem,
                                                            ignoringURLExclusions: ignoringURLExclusions) {
                                    children.append(childSnapshot)
                                } else {
                                    partial = true
                                }
                            }
                            if !children.isEmpty && partial {
                                isPartiallyMigrated = true
                            }
                        }
                    }
                }
            case .typeRegular:
                type = .file
            case .typeSymbolicLink:
                type = .symlink
            case .typeSocket:
                MLogger.main.log("fileScanner.scan: socket file detected - \(url.relativePath)")
                return nil
            case .typeBlockSpecial, .typeCharacterSpecial, .typeUnknown:
                // Named pipes (reported as unknown), devices: their content can't be copied and
                // opening a pipe for reading blocks until something writes to it.
                MLogger.main.log("fileScanner.scan: skipping special file type \(filetype.rawValue) at \(url.relativePath)", type: .default)
                return nil
            default:
                type = .file
            }
        } catch {
            MLogger.main.log("fileScanner.scan: could not get attributes for file - \(url.relativePath) - \(error.localizedDescription)", type: .fault)
            type = .file
        }

        children.sort { (file1, file2) in
            if file1.type != file2.type {
                return file1.type.sortOrder < file2.type.sortOrder
            } else {
                return file1.name < file2.name
            }
        }

        return MigratorFileSnapshot(type: type,
                                    url: trackedURL,
                                    name: name,
                                    isHidden: isHidden,
                                    hLevel: level,
                                    isPartiallyMigrated: isPartiallyMigrated,
                                    ignoresURLExclusions: ignoringURLExclusions,
                                    children: children)
    }

    /// Scans the immediate children of a directory URL, without any depth limit on the single
    /// level being scanned. Mirrors the previous `MigratorFile.fetchUnretainedChilds()`.
    static func scanChildren(of url: URL, ignoringURLExclusions: Bool = false) async -> [MigratorFileSnapshot] {
        guard let childURLs = try? FileManager.default.contentsOfDirectory(at: url,
                                                                            includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return [] }

        let batchSize = 20
        var tempChilds: [MigratorFileSnapshot] = []
        tempChilds.reserveCapacity(childURLs.count)
        await withTaskGroup(of: [MigratorFileSnapshot].self) { group in
            for batch in stride(from: 0, to: childURLs.count, by: batchSize)
                .map({ Array(childURLs[$0..<min($0 + batchSize, childURLs.count)]) }) {
                group.addTask(priority: .utility) {
                    var batchResults: [MigratorFileSnapshot] = []
                    batchResults.reserveCapacity(batch.count)
                    for childURL in batch {
                        guard (try? childURL.checkResourceIsReachable()) != false else {
                            MLogger.main.log("fileScanner.scanChildren: file not reachable - \(childURL.relativePath)", type: .fault)
                            continue
                        }
                        if let childSnapshot = scan(url: childURL, ignoringURLExclusions: ignoringURLExclusions) {
                            batchResults.append(childSnapshot)
                        }
                    }
                    return batchResults
                }
            }
            for await batchResults in group {
                tempChilds.append(contentsOf: batchResults)
            }
        }
        tempChilds.sort { (file1, file2) in
            if file1.type != file2.type {
                return file1.type.sortOrder < file2.type.sortOrder
            } else {
                return file1.name < file2.name
            }
        }
        return tempChilds
    }

    /// Computes the allocated size (in bytes) of a single file-system item (not recursing into
    /// directories). Used for the `.file`/`.symlink`/directory-self-size part of
    /// `MigratorFile.fetchFileSizeAndCount()`.
    static func allocatedSize(of url: URL) -> Int {
        return (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0) ?? 0
    }

    /// Recursively computes the size and file count of a tree, entirely off the main actor.
    ///
    /// `MigratorFile.fetchFileSizeAndCount()` builds a cheap `FileSizeInput` snapshot of its
    /// (already-retained, main-actor) object graph, awaits this once, then writes the matching
    /// `FileSizeResult` values back onto each retained node. That keeps every bit of the recursive
    /// disk I/O and summation off the main actor - critical for a real home folder, which can
    /// recurse through tens of thousands of nodes; routing each one through the main actor (as an
    /// earlier version of this code did) made size calculation dramatically slower, to the point
    /// of looking hung.
    static func computeSize(for input: FileSizeInput) async -> FileSizeResult {
        switch input.type {
        case .app:
            var size = 0
            var count = 0
            if let totals = try? await input.url.directoryAllocatedSizeAndItemCount() {
                size = totals.size
                count = totals.count + 1
            }
            return FileSizeResult(size: size, count: count, childResults: [])
        case .socket:
            return FileSizeResult(size: 0, count: 0, childResults: [])
        case .directory:
            let tempSize = allocatedSize(of: input.url)
            // Empty `input.children` means the retained object graph wasn't eagerly expanded this
            // deep (see `scan(url:level:...)`'s depth cap), so scan this level fresh - mirrors the
            // previous `fetchUnretainedChilds()` behavior, just without ever materializing
            // `MigratorFile` objects for a subtree nothing will display.
            let children = input.children.isEmpty
                ? await scanChildren(of: input.url, ignoringURLExclusions: input.ignoresURLExclusions).map { FileSizeInput(snapshot: $0) }
                : input.children

            var childResults: [FileSizeResult?] = Array(repeating: nil, count: children.count)
            let batchSize = 10
            var batchStart = 0
            while batchStart < children.count {
                let batchEnd = min(batchStart + batchSize, children.count)
                await withTaskGroup(of: (Int, FileSizeResult).self) { group in
                    for index in batchStart..<batchEnd {
                        group.addTask {
                            (index, await computeSize(for: children[index]))
                        }
                    }
                    for await (index, result) in group {
                        childResults[index] = result
                    }
                }
                batchStart = batchEnd
            }
            let resolvedChildResults = childResults.compactMap { $0 }
            let size = tempSize + resolvedChildResults.reduce(0) { $0 + $1.size }
            let count = 1 + resolvedChildResults.reduce(0) { $0 + $1.count }
            // Only propagate child results back when they correspond to retained nodes the caller
            // can actually write onto; a freshly-scanned (unretained) subtree has nothing to assign.
            return FileSizeResult(size: size, count: count, childResults: input.children.isEmpty ? [] : resolvedChildResults)
        default:
            return FileSizeResult(size: allocatedSize(of: input.url), count: 1, childResults: [])
        }
    }
}

/// Nonisolated input to `FileScanner.computeSize(for:)`: a cheap (no I/O) mirror of a `MigratorFile`
/// object graph's `url`/`type`/`childFiles`, built synchronously on the main actor so the actual
/// size computation can then run entirely off it.
struct FileSizeInput: Sendable {
    let url: URL
    let type: FileType
    let children: [FileSizeInput]
    /// Carried so an unexpanded directory is re-scanned under the same exclusion rules it was built with.
    let ignoresURLExclusions: Bool

    init(url: URL, type: FileType, children: [FileSizeInput], ignoresURLExclusions: Bool = false) {
        self.url = url
        self.type = type
        self.children = children
        self.ignoresURLExclusions = ignoresURLExclusions
    }

    init(snapshot: MigratorFileSnapshot) {
        self.url = snapshot.url.fullURL()
        self.type = snapshot.type
        self.children = snapshot.children.map { FileSizeInput(snapshot: $0) }
        self.ignoresURLExclusions = snapshot.ignoresURLExclusions
    }
}

/// Mirrors the shape of a `FileSizeInput` tree: the computed size/count for that node, plus one
/// result per retained child (empty when the node's children weren't part of the input tree).
struct FileSizeResult: Sendable {
    let size: Int
    let count: Int
    let childResults: [FileSizeResult]
}
