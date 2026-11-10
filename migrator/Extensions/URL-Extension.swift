//
//  URL-Extension.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 31/01/2024.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

extension URL {
    /// Checks if the URL represents a directory and is reachable.
    ///
    /// - Returns: A Boolean value indicating whether the URL represents a reachable directory.
    func isDirectoryAndReachable() throws -> Bool {
        guard try resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            return false
        }
        return try checkResourceIsReachable()
    }

    /// Calculates the total allocated size of files within the directory.
    /// - Parameter includingSubfolders: A Boolean value indicating whether to include subfolders in the calculation.
    /// - Returns: The total allocated size of files within the directory, or nil if the directory is not reachable or an error occurs.
    func directoryTotalAllocatedSize() async throws -> Int? {
        try await directoryAllocatedSizeAndItemCount()?.size
    }

    func directoryTotalNumberOfFiles() async throws -> Int? {
        try await directoryAllocatedSizeAndItemCount()?.count
    }

    /// The total allocated size and the number of items inside the directory, computed in a single
    /// pass over its contents.
    ///
    /// The walk is blocking disk I/O (an app bundle can hold hundreds of thousands of items), so it
    /// runs on a GCD queue: running it directly in this `async` function would occupy one of the few
    /// threads of Swift's cooperative pool for its whole duration, and several of these at once (one
    /// per app) starve every other task - the size calculation then looks like it never finishes.
    func directoryAllocatedSizeAndItemCount() async throws -> (size: Int, count: Int)? {
        guard try isDirectoryAndReachable() else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: self.transferableDescendantsTotals())
            }
        }
    }

    /// Walks the directory once, leaving out what the transfer skips (see
    /// `Utils.FileManagerHelpers.shouldSkipDescendantForTransfer`) together with everything below it,
    /// so sizes and counts match what is actually sent. An item whose size can't be read counts as 0.
    private func transferableDescendantsTotals() -> (size: Int, count: Int)? {
        guard let enumerator = FileManager.default.enumerator(at: self,
                                                              includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return nil }
        var size = 0
        var count = 0
        while let url = enumerator.nextObject() as? URL {
            if Utils.FileManagerHelpers.shouldSkipDescendantForTransfer(url) {
                enumerator.skipDescendants()
                continue
            }
            size += (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0
            count += 1
        }
        return (size, count)
    }
}
