//
//  MigratorFileURL.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 30/01/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// Struct representing a file URL in a migration context.
struct MigratorFileURL: Codable, Equatable, Hashable {
    /// Enum defining different source directory types.
    enum MigratorURLSource: UInt8, Codable {
        case documentsFolder
        case desktopFolder
        case userFolder
        case applicationsFolder
        case unknown
    }
    
    // MARK: - Variables
    
    /// The source directory type.
    var source: MigratorURLSource
    
    // MARK: - Private Variables
    
    /// The relative path to the file.
    private var relativePath: String
    
    // MARK: - Initializers
    
    /// Initializes a `MigratorFileURL` instance with a given URL.
    /// - Parameter url: The URL to initialize from.
    init(with url: URL) {
        var relativePath = url.relativePath
        let userFolder = FileManager.default.homeDirectoryForCurrentUser.relativePath
        let documentsFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.relativePath
        let desktopFolder = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!.relativePath
        let applicationsFolder = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first!.relativePath
        
        if relativePath.contains("\(desktopFolder)") {
            relativePath.removeSubrange(Range(uncheckedBounds: (lower: desktopFolder.startIndex, upper: desktopFolder.endIndex)))
            if !relativePath.isEmpty {
                _ = relativePath.removeFirst()
            }
            self.source = .desktopFolder
            self.relativePath = relativePath
        } else if relativePath.contains("\(documentsFolder)") {
            relativePath.removeSubrange(Range(uncheckedBounds: (lower: documentsFolder.startIndex, upper: documentsFolder.endIndex)))
            if !relativePath.isEmpty {
                _ = relativePath.removeFirst()
            }
            self.source = .documentsFolder
            self.relativePath = relativePath
        } else if relativePath.contains("\(userFolder)") {
            relativePath.removeSubrange(Range(uncheckedBounds: (lower: userFolder.startIndex, upper: userFolder.endIndex)))
            if !relativePath.isEmpty {
                _ = relativePath.removeFirst()
            }
            self.source = .userFolder
            self.relativePath = relativePath
        } else if relativePath.contains("\(applicationsFolder)") {
            relativePath.removeSubrange(Range(uncheckedBounds: (lower: applicationsFolder.startIndex, upper: applicationsFolder.endIndex)))
            if !relativePath.isEmpty {
                _ = relativePath.removeFirst()
            }
            self.source = .applicationsFolder
            self.relativePath = relativePath
        } else {
            self.source = .unknown
            self.relativePath = relativePath
        }
    }
    
    /// The full URL based on the source and relative path.
    func fullURL() -> URL {
        switch source {
        case .documentsFolder:
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(relativePath)
        case .desktopFolder:
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!.appendingPathComponent(relativePath)
        case .userFolder:
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relativePath)
        case .applicationsFolder:
            return FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first!.appendingPathComponent(relativePath)
        case .unknown:
            return URL(string: relativePath)!
        }
    }
}
