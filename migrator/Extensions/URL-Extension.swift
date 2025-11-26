//
//  URL-Extension.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 31/01/2024.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

extension URL {
    /// Static instance of ByteCountFormatter for formatting byte counts.
    private static let byteCountFormatter = ByteCountFormatter()

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
    ///
    /// - Parameter includingSubfolders: A Boolean value indicating whether to include subfolders in the calculation.
    /// - Returns: The total allocated size of files within the directory, or nil if the directory is not reachable or an error occurs.
    func directoryTotalAllocatedSize() async throws -> Int? {
        guard try isDirectoryAndReachable() else { return nil }
        guard let urls = FileManager.default.enumerator(at: self, includingPropertiesForKeys: nil)?.allObjects as? [URL] else { return nil }
        return try urls.lazy.reduce(0) {
            (try $1.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0) + $0
        }
    }
    
    func directoryTotalNumberOfFiles() async throws -> Int? {
        guard try isDirectoryAndReachable() else { return nil }
        guard let urls = FileManager.default.enumerator(at: self, includingPropertiesForKeys: nil)?.allObjects as? [URL] else { return nil }
        return urls.lazy.count
    }
}
