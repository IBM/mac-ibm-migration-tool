//
//  MigratorFileURL.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 30/01/2024.
//  © Copyright IBM Corp. 2023, 2026
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
    var relativePath: String
    
    // MARK: - Initializers

    /// Initializes a `MigratorFileURL` from its parts. Declared explicitly because `init(with:)`
    /// below suppresses the synthesized memberwise initializer.
    init(source: MigratorURLSource, relativePath: String) {
        self.source = source
        self.relativePath = relativePath
    }

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
            return URL(fileURLWithPath: relativePath)
        }
    }
}

// MARK: - Receive-side validation

extension MigratorFileURL {
    /// Reasons a peer-supplied path is refused on the receiving side.
    enum ValidationError: LocalizedError {
        case untrustedSource
        case invalidRelativePath(String)
        case outsideAllowedRoots(String)

        var errorDescription: String? {
            switch self {
            case .untrustedSource:
                return "path has no recognised source directory"
            case .invalidRelativePath(let path):
                return "invalid relative path \"\(path)\""
            case .outsideAllowedRoots(let path):
                return "\"\(path)\" is outside the directories a migration may write to"
            }
        }
    }

    /// The only directory trees a migration is allowed to write into, symlinks resolved.
    private static var allowedReceiveRoots: [URL] {
        [FileManager.default.homeDirectoryForCurrentUser,
         URL(fileURLWithPath: "/Applications", isDirectory: true)]
            .compactMap { resolvingSymlinks(of: $0, includingLeaf: true) }
    }

    /// Returns the location this peer-supplied path should be written to, or throws if it could
    /// land outside `allowedReceiveRoots`.
    ///
    /// Rejects `.unknown` sources, absolute or `..`-containing relative paths, and anything that
    /// resolves (through existing symlinks, including dangling ones) outside the allowed roots.
    /// The returned URL is fully resolved, so callers operate on the location that was checked.
    /// - Parameter resolvingFinalComponent: Pass `false` when the last path component is about to
    ///   be replaced rather than written through (creating a symlink), so a pre-existing link
    ///   there is judged by where it lives, not by where it points.
    func validatedReceiveURL(resolvingFinalComponent: Bool = true) throws -> URL {
        guard source != .unknown else {
            throw ValidationError.untrustedSource
        }
        guard !relativePath.hasPrefix("/"), !relativePath.contains("\0"),
              !relativePath.split(separator: "/").contains("..") else {
            throw ValidationError.invalidRelativePath(relativePath)
        }
        guard let resolved = Self.resolvingSymlinks(of: fullURL(), includingLeaf: resolvingFinalComponent) else {
            throw ValidationError.outsideAllowedRoots(fullURL().path)
        }
        guard Self.isWithinAllowedRoots(resolved) else {
            throw ValidationError.outsideAllowedRoots(resolved.path)
        }
        return resolved
    }

    /// Throws if a symlink created at `linkURL` would point outside the allowed roots.
    /// - Parameters:
    ///   - destination: The peer-supplied link target, absolute or relative to the link's directory.
    ///   - linkURL: The already-validated location of the link itself.
    static func validateSymlinkTarget(_ destination: String, linkURL: URL) throws {
        guard !destination.isEmpty, !destination.contains("\0") else {
            throw ValidationError.invalidRelativePath(destination)
        }
        let base = destination.hasPrefix("/")
            ? URL(fileURLWithPath: destination)
            : linkURL.deletingLastPathComponent().appendingPathComponent(destination)
        guard let resolved = resolvingSymlinks(of: base, includingLeaf: true) else {
            throw ValidationError.outsideAllowedRoots(base.path)
        }
        guard isWithinAllowedRoots(resolved) else {
            throw ValidationError.outsideAllowedRoots(resolved.path)
        }
    }

    /// Resolves `url` component by component, following every symlink it meets - including dangling
    /// ones, which `resolvingSymlinksInPath()` leaves untouched even though a write through them
    /// would create the file at the link's target. Components that don't exist yet are kept as is.
    /// - Parameter includingLeaf: When false, the last component is appended without being followed.
    /// - Returns: The resolved URL, or nil if the path loops through more than 40 symlinks.
    private static func resolvingSymlinks(of url: URL, includingLeaf: Bool) -> URL? {
        var components = url.standardizedFileURL.pathComponents.filter { $0 != "/" }
        let leaf = includingLeaf ? nil : components.popLast()
        var pending = Array(components.reversed())
        var resolved = URL(fileURLWithPath: "/")
        var followedLinks = 0

        while let component = pending.popLast() {
            switch component {
            case ".":
                continue
            case "..":
                resolved.deleteLastPathComponent()
                continue
            default:
                break
            }
            let candidate = resolved.appendingPathComponent(component)
            if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: candidate.path) {
                followedLinks += 1
                guard followedLinks <= 40 else { return nil }
                if destination.hasPrefix("/") {
                    resolved = URL(fileURLWithPath: "/")
                }
                pending.append(contentsOf: destination.split(separator: "/").map(String.init).reversed())
            } else {
                resolved = candidate
            }
        }
        if let leaf {
            resolved.appendPathComponent(leaf)
        }
        return resolved.standardizedFileURL
    }

    private static func isWithinAllowedRoots(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return allowedReceiveRoots.contains { root in
            path == root.path || path.hasPrefix(root.path.hasSuffix("/") ? root.path : root.path + "/")
        }
    }
}

extension FileMessage {
    /// Peer-supplied attributes reduced to what a migration needs: permission bits (without
    /// setuid/setgid/sticky) and dates. Ownership, flags and anything else are dropped.
    ///
    /// Use `sanitizedDirectoryAttributes` for directories.
    var sanitizedAttributes: [FileAttributeKey: Any] {
        var result: [FileAttributeKey: Any] = [:]
        if let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue {
            result[.posixPermissions] = NSNumber(value: permissions & 0o777)
        }
        if let created = attributes[.creationDate] as? Date {
            result[.creationDate] = created
        }
        if let modified = attributes[.modificationDate] as? Date {
            result[.modificationDate] = modified
        }
        return result
    }

    /// `sanitizedAttributes` for a directory, with owner read/write/execute always kept.
    ///
    /// ACLs aren't migrated, so a source folder whose owner access comes only from an ACL (macOS
    /// can leave `~/Public` as `d---r-xr-x+`) would otherwise arrive unreadable and untraversable
    /// for its own owner - and since directories are created before their contents, every file
    /// inside would then fail to be written.
    var sanitizedDirectoryAttributes: [FileAttributeKey: Any] {
        var result = sanitizedAttributes
        let permissions = (result[.posixPermissions] as? NSNumber)?.intValue ?? 0o755
        result[.posixPermissions] = NSNumber(value: permissions | 0o700)
        return result
    }
}
