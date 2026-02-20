//
//  ArchitectureDetector.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 21/01/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// Utility class for detecting application architectures
class ArchitectureDetector {
    
    // MARK: - Static Properties
    
    /// Shared singleton instance
    static let shared = ArchitectureDetector()
    /// Logger instance for architecture detection
    private let logger = MLogger.main
    
    // MARK: - Private Properties
    
    /// Cache for architecture detection results to avoid redundant checks
    private var architectureCache: [URL: Set<AppArchitecture>] = [:]
    /// Queue for thread-safe cache access
    private let cacheQueue = DispatchQueue(label: "com.ibm.datashift.architecturedetector.cache", attributes: .concurrent)
    
    // MARK: - Initializers
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Detects the architectures supported by an application bundle
    /// - Parameter url: URL of the application bundle
    /// - Returns: Set of supported architectures
    func detectAppArchitecture(at url: URL) -> Set<AppArchitecture> {
        // Check cache first
        if let cached = getCachedArchitecture(for: url) {
            logger.log("architectureDetector.detectAppArchitecture: Using cached result for \(url.lastPathComponent)", type: .debug)
            return cached
        }
        logger.log("architectureDetector.detectAppArchitecture: Detecting architecture for \(url.lastPathComponent)", type: .debug)
        guard url.pathExtension == "app" else {
            logger.log("architectureDetector.detectAppArchitecture: Not an app bundle: \(url.lastPathComponent)", type: .debug)
            return []
        }
        guard let executableURL = findExecutable(in: url) else {
            logger.log("architectureDetector.detectAppArchitecture: No executable found in \(url.lastPathComponent)", type: .debug)
            return []
        }
        let architectures = detectArchitectureUsingFile(at: executableURL)

        cacheArchitecture(architectures, for: url)
        logger.log("architectureDetector.detectAppArchitecture: Detected architectures for \(url.lastPathComponent): \(architectures.map { $0.rawValue }.joined(separator: ", "))", type: .debug)
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
    func isUniversalBinary(at url: URL) -> Bool {
        let architectures = detectAppArchitecture(at: url)
        return architectures.contains(.intel) && architectures.contains(.appleSilicon)
    }
    
    /// Clears the architecture cache
    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.architectureCache.removeAll()
        }
        logger.log("architectureDetector.clearCache: Cache cleared", type: .debug)
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
                logger.log("architectureDetector.detectArchitectureUsingFile: file output: \(output)", type: .debug)
                
                if output.contains("x86_64") || output.contains("x86-64") {
                    architectures.insert(.intel)
                }
                if output.contains("arm64") {
                    architectures.insert(.appleSilicon)
                }
            }
        } catch {
            logger.log("architectureDetector.detectArchitectureUsingFile: Failed to run file command: \(error.localizedDescription)", type: .error)
        }
        
        return architectures
    }
    
    /// Gets cached architecture for a URL
    /// - Parameter url: URL to check
    /// - Returns: Cached architectures, or nil if not cached
    private func getCachedArchitecture(for url: URL) -> Set<AppArchitecture>? {
        return cacheQueue.sync {
            return architectureCache[url]
        }
    }
    
    /// Caches architecture detection result
    /// - Parameters:
    ///   - architectures: Set of architectures to cache
    ///   - url: URL to cache for
    private func cacheArchitecture(_ architectures: Set<AppArchitecture>, for url: URL) {
        cacheQueue.async(flags: .barrier) {
            self.architectureCache[url] = architectures
        }
    }
}
