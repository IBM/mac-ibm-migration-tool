//
//  DiscoveredApplication.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 21/01/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import Combine

/// Class representing a discovered application with architecture information
@MainActor
final class DiscoveredApplication: ObservableObject, Identifiable {
    
    // MARK: - Published Variables
    
    /// Published property to track if the application is selected for migration
    @Published var isSelected: Bool = false
    /// Set of architectures supported by this application
    @Published private(set) var architectures: Set<AppArchitecture>
    /// Published property for discovered app support files information
    @Published var appInfo: AppInfo?
    
    // MARK: - Constants
    
    /// Unique identifier for the application
    nonisolated let id: UUID
    /// Name of the application
    let name: String
    /// URL of the application bundle
    let url: URL
    /// Size of the application bundle in bytes
    let fileSize: Int
    /// Reference to the associated MigratorFile for migration purposes
    let migratorFile: MigratorFile

    // MARK: - Variables
    
    /// The overall architecture type of the application
    var architectureType: ArchitectureType {
        if architectures.isEmpty {
            return .unknown
        } else if architectures.contains(.intel) && architectures.contains(.appleSilicon) {
            return .universal
        } else if architectures.contains(.intel) {
            return .intelOnly
        } else if architectures.contains(.appleSilicon) {
            return .appleSiliconOnly
        } else {
            return .unknown
        }
    }
    /// Returns a user-friendly description of the architecture
    var architectureDescription: String {
        switch architectureType {
        case .intelOnly:
            return "app.architecture.description.intelOnly".localized
        case .appleSiliconOnly:
            return "app.architecture.description.appleSiliconOnly".localized
        case .universal:
            return "app.architecture.description.universal".localized
        case .unknown:
            return "app.architecture.description.unknown".localized
        }
    }
    
    // MARK: - Initializers
    
    /// Initialize a new DiscoveredApplication
    /// - Parameters:
    ///   - name: Name of the application
    ///   - url: URL of the application bundle
    ///   - fileSize: Size of the application in bytes
    ///   - architectures: Set of supported architectures
    ///   - migratorFile: Reference to associated MigratorFile
    init(name: String, url: URL, fileSize: Int, architectures: Set<AppArchitecture>, migratorFile: MigratorFile) {
        self.id = UUID()
        self.name = name
        self.url = url
        self.fileSize = fileSize
        self.architectures = architectures
        self.migratorFile = migratorFile
    }
    
    /// Convenience initializer from a MigratorFile
    /// - Parameters:
    ///   - migratorFile: The MigratorFile to create from
    ///   - architectures: Set of supported architectures
    convenience init?(from migratorFile: MigratorFile, architectures: Set<AppArchitecture>) {
        guard migratorFile.type == .app else { return nil }
        
        self.init(name: migratorFile.name,
                  url: migratorFile.url.fullURL(),
                  fileSize: migratorFile.fileSize,
                  architectures: architectures,
                  migratorFile: migratorFile)
    }
    
    // MARK: - Public Methods
    
    /// Updates the architectures for this application
    /// - Parameter newArchitectures: The new set of architectures
    func updateArchitectures(_ newArchitectures: Set<AppArchitecture>) {
        self.architectures = newArchitectures
    }
    
    /// Determines if this application requires Rosetta 2 on the destination device
    /// - Parameter destinationArchitecture: The architecture of the destination device
    /// - Returns: True if Rosetta 2 is required, false otherwise
    func requiresRosetta(on destinationArchitecture: AppArchitecture) -> Bool {
        return destinationArchitecture == .appleSilicon && architectureType == .intelOnly
    }
    
    /// Returns all discovered support files as MigratorFile objects
    func supportFiles() async -> [MigratorFile] {
        guard AppContext.shouldMigrateAppSupportFiles, let appInfo = appInfo else { return [] }
        var files: [MigratorFile] = []
        for path in appInfo.allDiscoveredPaths {
            if let file = await MigratorFile.make(with: path) {
                files.append(file)
            }
        }
        return files
    }
    
    /// Returns the calculated app bundle size, falling back to the initial discovery value.
    var appBundleSize: Int {
        if migratorFile.fileSize != -1 {
            return migratorFile.fileSize
        }
        return max(fileSize, 0)
    }
    
    /// Returns the total size including app bundle and support files when enabled.
    var totalSize: Int {
        let supportSize = AppContext.shouldMigrateAppSupportFiles ? appInfo?.cachedTotalSize ?? 0 : 0
        return appBundleSize + supportSize
    }
    
    /// Asynchronously calculates total size including support files when enabled.
    /// - Returns: Total size in bytes.
    func getTotalSizeAsync() async -> Int {
        await migratorFile.fetchFileSizeAndCount()
        guard AppContext.shouldMigrateAppSupportFiles, let appInfo = appInfo else { return appBundleSize }
        let supportSize = await appInfo.getTotalSize()
        return appBundleSize + supportSize
    }
    
    /// Returns the count of discovered support files
    var supportFileCount: Int {
        guard AppContext.shouldMigrateAppSupportFiles else { return 0 }
        return appInfo?.discoveredFileCount ?? 0
    }
    
    /// Returns a breakdown of support file sizes by category
    /// - Returns: Dictionary with category names and sizes
    func getSupportFileSizeBreakdown() async -> [String: Int] {
        guard AppContext.shouldMigrateAppSupportFiles, let appInfo = appInfo else { return [:] }
        return await appInfo.getSizeBreakdown()
    }
}

// MARK: - Hashable Conformance

extension DiscoveredApplication: Hashable {
    nonisolated static func == (lhs: DiscoveredApplication, rhs: DiscoveredApplication) -> Bool {
        return lhs.id == rhs.id
    }
    
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
