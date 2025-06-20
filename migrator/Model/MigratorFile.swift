//
//  MigratorFile.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 30/01/2024.
//  © Copyright IBM Corp. 2023, 2024
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
    
    var allowListed: Bool = false
    
    // MARK: - Intializers
    
    // swiftlint:disable function_body_length
    /// Asynchronous initialization to fetch file attributes and child files from a file URL.
    /// - Parameter url: URL of the source file.
    init(with url: URL, allowListed: Bool = false, level: Int = 0) {
        self.name = url.lastPathComponent
        self.url = MigratorFileURL(with: url)
        self.hLevel = level
        self.isHidden = url.lastPathComponent.hasPrefix(".")
        self.allowListed = allowListed
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
                    for childURL in childsURL {
                        if allowListed {
                            if AppContext.explicitAllowList.contains(where: { url in
                                return url?.absoluteString == childURL.absoluteString
                            }) {
                                let childFile = MigratorFile(with: childURL, level: hLevel+1)
                                self.childFiles.checkAndAppendFile(childFile)
                            } else if AppContext.explicitAllowList.contains(where: { url in
                                return url?.absoluteString.contains(childURL.absoluteString) ?? false
                            }) {
                                let childFile = MigratorFile(with: childURL, allowListed: true, level: hLevel+1)
                                self.childFiles.checkAndAppendFile(childFile)
                            }
                            continue
                        }
                        guard !AppContext.urlExclusionList.contains(childURL) &&
                                !AppContext.excludedFileExtensions.contains(childURL.lastPathComponent) &&
                                childURL.lastPathComponent.first != "~" else {
                            if AppContext.explicitAllowList.contains(where: { url in
                                return url?.absoluteString.contains(childURL.absoluteString) ?? false
                            }) {
                                let childFile = MigratorFile(with: childURL, allowListed: true, level: hLevel+1)
                                self.childFiles.checkAndAppendFile(childFile)
                            }
                            continue
                        }
                        let childFile = MigratorFile(with: childURL, level: hLevel+1)
                        self.childFiles.checkAndAppendFile(childFile)
                    }
                }
            case .typeRegular:
                self.type = .file
            case .typeSymbolicLink:
                self.type = .symlink
            case .typeSocket:
                self.type = .socket
            default:
                self.type = .file
            }
        } else {
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
    
    // MAKR: - Public Methods

    /// Calculate the current file size in bytes.
    func fetchFileSizeAndCount() async {
        guard self.fileSize == -1 else { return }
        if type == .app {
            if let size = try? await self.url.fullURL().directoryTotalAllocatedSize() {
                await MainActor.run {
                    self.fileSize = size
                }
            }
            if let filesCount = try? await self.url.fullURL().directoryTotalNumberOfFiles() {
                await MainActor.run {
                    self.numberOfFiles = filesCount + 1
                }
            }
        } else if type == .socket {
            self.fileSize = 0
            self.numberOfFiles = 1
        } else if type == .directory {
            let availableChildFiles = self.childFiles.isEmpty ? await self.fetchUnretainedChilds() : self.childFiles
            for file in availableChildFiles {
                await file.fetchFileSizeAndCount()
            }
            let tempSize = (try? self.url.fullURL().resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0) ?? 0
            let totalSize = availableChildFiles.reduce(tempSize) { return $0 + $1.fileSize }
            let totalCount = availableChildFiles.reduce(1) { return $0 + $1.numberOfFiles }
            await MainActor.run {
                self.fileSize = totalSize
                self.numberOfFiles = totalCount
            }
        } else {
            await MainActor.run {
                self.fileSize = (try? self.url.fullURL().resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0) ?? 0
                self.numberOfFiles = 1
            }
        }
    }
    
    func fetchUnretainedChilds() async -> [MigratorFile] {
        if let childsURL = try? FileManager.default.contentsOfDirectory(at: url.fullURL(), includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) {
            var tempChilds: [MigratorFile] = []
            for childURL in childsURL {
                if allowListed {
                    if AppContext.explicitAllowList.contains(where: { url in
                        return url?.absoluteString == childURL.absoluteString
                    }) {
                        let childFile = MigratorFile(with: childURL)
                        tempChilds.checkAndAppendFile(childFile)
                    } else if AppContext.explicitAllowList.contains(where: { url in
                        return url?.absoluteString.contains(childURL.absoluteString) ?? false
                    }) {
                        let childFile = MigratorFile(with: childURL, allowListed: true)
                        tempChilds.checkAndAppendFile(childFile)
                    }
                    continue
                }
                guard !AppContext.urlExclusionList.contains(childURL) &&
                        !AppContext.excludedFileExtensions.contains(childURL.lastPathComponent) &&
                        childURL.lastPathComponent.first != "~" else {
                    if AppContext.explicitAllowList.contains(where: { url in
                        return url?.absoluteString.contains(childURL.absoluteString) ?? false
                    }) {
                        let childFile = MigratorFile(with: childURL, allowListed: true)
                        tempChilds.checkAndAppendFile(childFile)
                    }
                    continue
                }
                let childFile = MigratorFile(with: childURL)
                tempChilds.checkAndAppendFile(childFile)
            }
            return tempChilds
        }
        return []
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
