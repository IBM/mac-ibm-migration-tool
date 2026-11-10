//
//  FileSizeCache.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 08/05/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import Synchronization

/// Singleton class that caches file size calculations to avoid redundant disk operations
/// across multiple migration options (Lite, Complete, Advanced).
final class FileSizeCache: Sendable {
    
    // MARK: - Singleton
    
    /// Shared instance for global access
    static let shared = FileSizeCache()
    
    // MARK: - Structures
    
    /// Structure to hold cached size information
    struct CachedSizeInfo: Sendable {
        let size: Int
        let numberOfFiles: Int
        let timestamp: Date
    }
    
    // MARK: - Private Properties
    
    /// Cache storage: [URL: CachedSizeInfo]
    private let cache = Mutex<[URL: CachedSizeInfo]>([:])
    
    /// Cache expiration interval (1 hour)
    private let cacheExpirationInterval: TimeInterval = 3600
    
    // MARK: - Initializer
    
    /// Private initializer to enforce singleton pattern
    private init() {
        MLogger.main.log("fileSizeCache.init: Initialized")
    }
    
    // MARK: - Public Methods
    
    /// Retrieves cached size information for a given URL
    /// - Parameter url: The URL to look up in the cache
    /// - Returns: Cached size info if available and not expired, nil otherwise
    func getCachedSize(for url: URL) -> CachedSizeInfo? {
        guard let cached = cache.withLock({ $0[url] }) else {
            return nil
        }
        
        // Check if cache entry has expired
        let elapsed = Date().timeIntervalSince(cached.timestamp)
        if elapsed > cacheExpirationInterval {
            MLogger.main.log("fileSizeCache.getCachedSize: Cache expired for \(url.lastPathComponent) (age: \(Int(elapsed))s)")
            return nil
        }
        
        MLogger.main.log("fileSizeCache.getCachedSize: Cache hit for \(url.lastPathComponent) (size: \(cached.size) bytes)")
        return cached
    }
    
    /// Stores size information in the cache for a given URL
    /// - Parameters:
    ///   - url: The URL to cache
    ///   - size: The total size in bytes
    ///   - numberOfFiles: The number of files (1 for single files, more for directories)
    func setCachedSize(for url: URL, size: Int, numberOfFiles: Int) {
        let info = CachedSizeInfo(size: size, numberOfFiles: numberOfFiles, timestamp: Date())
        cache.withLock { $0[url] = info }
        MLogger.main.log("fileSizeCache.setCachedSize: Cached \(url.lastPathComponent) (size: \(size) bytes, files: \(numberOfFiles))")
    }
    
    /// Clears all cached entries
    func clearCache() {
        let count = cache.withLock { cache in
            let count = cache.count
            cache.removeAll()
            return count
        }
        MLogger.main.log("fileSizeCache.clearCache: Cleared \(count) cached entries")
    }
    
    /// Returns the number of cached entries
    /// - Returns: Count of cached items
    func cacheCount() -> Int {
        return cache.withLock { $0.count }
    }
    
    /// Removes expired entries from the cache
    func pruneExpiredEntries() {
        let now = Date()
        let expirationInterval = cacheExpirationInterval
        let removedCount = cache.withLock { cache in
            let initialCount = cache.count
            cache = cache.filter { _, value in
                now.timeIntervalSince(value.timestamp) <= expirationInterval
            }
            return initialCount - cache.count
        }
        if removedCount > 0 {
            MLogger.main.log("fileSizeCache.pruneExpiredEntries: Pruned \(removedCount) expired entries")
        }
    }
}
