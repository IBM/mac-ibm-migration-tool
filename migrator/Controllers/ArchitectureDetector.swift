//
//  ArchitectureDetector.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 21/01/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import Synchronization

/// Utility class for detecting application architectures
final class ArchitectureDetector: Sendable {
    
    // MARK: - Static Properties
    
    /// Shared singleton instance
    static let shared = ArchitectureDetector()
    /// Logger instance for architecture detection
    private let logger = MLogger.main.scoped(to: .discovery)
    
    // MARK: - Private Properties
    
    /// Cache for architecture detection results to avoid redundant checks
    private let architectureCache = Mutex<[URL: Set<AppArchitecture>]>([:])
    
    // MARK: - Initializers
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Detects the architectures supported by an application bundle
    /// - Parameter url: URL of the application bundle
    /// - Returns: Set of supported architectures
    func detectAppArchitecture(at url: URL) async -> Set<AppArchitecture> {
        // Check cache first
        if let cached = getCachedArchitecture(for: url) {
            logger.log("architectureDetector.detectAppArchitecture: using cached result for \"\(url.lastPathComponent)\"")
            return cached
        }
        logger.log("architectureDetector.detectAppArchitecture: detecting architecture for \"\(url.lastPathComponent)\"")
        guard url.pathExtension == "app" else {
            logger.log("architectureDetector.detectAppArchitecture: not an app bundle -> \"\(url.lastPathComponent)\"")
            return []
        }
        guard let executableURL = findExecutable(in: url) else {
            logger.log("architectureDetector.detectAppArchitecture: no executable found in \"\(url.lastPathComponent)\"", type: .error)
            return []
        }
        // `detectArchitectureUsingFile` blocks on `Process.waitUntilExit()`. Run it on a dedicated
        // GCD queue rather than directly in this `async` function's body: a plain blocking call
        // inside a nonisolated async function still runs on Swift's shared cooperative thread
        // pool, and a blocked thread there can starve other concurrent work (e.g. the `TaskGroup`s
        // in `FileScanner` doing file-size calculation) that also needs that same limited pool.
        let architectures = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.detectArchitectureUsingFile(at: executableURL))
            }
        }

        cacheArchitecture(architectures, for: url)
        logger.log("architectureDetector.detectAppArchitecture: detected architectures for \"\(url.lastPathComponent)\" -> \(architectures.map { $0.rawValue }.joined(separator: ", "))")
        return architectures
    }
    
    /// Gets the current device's architecture
    /// - Returns: The architecture of the current device
    static func getCurrentDeviceArchitecture() -> AppArchitecture {
        #if arch(arm64)
        return .appleSilicon
        #elseif arch(x86_64)
        return .intel
        #else
        return .intel
        #endif
    }
    
    /// Checks if an application is a universal binary
    /// - Parameter url: URL of the application bundle
    /// - Returns: True if the application is universal, false otherwise
    func isUniversalBinary(at url: URL) async -> Bool {
        let architectures = await detectAppArchitecture(at: url)
        return architectures.contains(.intel) && architectures.contains(.appleSilicon)
    }
    
    /// Clears the architecture cache
    func clearCache() {
        architectureCache.withLock { $0.removeAll() }
        logger.log("architectureDetector.clearCache: cache cleared")
    }
    
    // MARK: - Private Methods
    
    /// Finds the main executable in an application bundle
    /// - Parameter bundleURL: URL of the application bundle
    /// - Returns: URL of the executable, or nil if not found
    private func findExecutable(in bundleURL: URL) -> URL? {
        let infoPlistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        
        if let infoPlist = NSDictionary(contentsOf: infoPlistURL),
           let executableName = infoPlist["CFBundleExecutable"] as? String {
            let executableURL = bundleURL.appendingPathComponent("Contents/MacOS/\(executableName)")
            if FileManager.default.fileExists(atPath: executableURL.path) {
                return executableURL
            }
        }
        
        let macOSURL = bundleURL.appendingPathComponent("Contents/MacOS")
        if let contents = try? FileManager.default.contentsOfDirectory(at: macOSURL, includingPropertiesForKeys: [.isExecutableKey]) {
            for fileURL in contents {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.isExecutableKey]),
                   resourceValues.isExecutable == true {
                    return fileURL
                }
            }
        }
        return nil
    }
    
    /// Fallback method to detect architecture using the file command
    /// - Parameter executableURL: URL of the executable file
    /// - Returns: Set of detected architectures
    private func detectArchitectureUsingFile(at executableURL: URL) -> Set<AppArchitecture> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/file")
        process.arguments = [executableURL.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        var architectures: Set<AppArchitecture> = []
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                logger.log("architectureDetector.detectArchitectureUsingFile: file command output -> \"\(output)\"")
                
                if output.contains("x86_64") || output.contains("x86-64") {
                    architectures.insert(.intel)
                }
                if output.contains("arm64") {
                    architectures.insert(.appleSilicon)
                }
            }
        } catch {
            logger.log("architectureDetector.detectArchitectureUsingFile: failed to run file command -> \"\(error.localizedDescription)\"", type: .error)
        }
        
        return architectures
    }
    
    /// Gets cached architecture for a URL
    /// - Parameter url: URL to check
    /// - Returns: Cached architectures, or nil if not cached
    private func getCachedArchitecture(for url: URL) -> Set<AppArchitecture>? {
        return architectureCache.withLock { $0[url] }
    }
    
    /// Caches architecture detection result
    /// - Parameters:
    ///   - architectures: Set of architectures to cache
    ///   - url: URL to cache for
    private func cacheArchitecture(_ architectures: Set<AppArchitecture>, for url: URL) {
        architectureCache.withLock { $0[url] = architectures }
    }
}
