//
//  TransferSkipTests.swift
//  migratorTests
//
//  Created by Simone Martorelli on 22/10/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import Testing
@testable import Mac_IBM_Data_Shift

/// Covers the rules that keep dataless placeholders and regenerable caches out of a transfer.
struct TransferSkipTests {

    private typealias Helpers = Utils.FileManagerHelpers

    // MARK: - isRegenerableCachePath

    @Test(arguments: [
        "/Users/test/Library/Caches",
        "/Users/test/Library/Containers/com.example.app/Data/Library/Caches",
        "/Users/test/Library/Group Containers/group.com.example/Library/Caches",
        "/Users/test/Library/Containers/com.example.app/Data/tmp"
    ])
    func regenerableCachePaths_areDetected(path: String) {
        #expect(Helpers.isRegenerableCachePath(URL(fileURLWithPath: path)))
    }

    @Test(arguments: [
        "/Users/test/Documents/Caches",
        "/Users/test/Library/Application Support",
        "/Users/test/Library/Caches/com.example.app",
        "/Users/test/Library/Containers/com.example.app/Data/Documents",
        "/Users/test/tmp",
        "/Users/test/Data/tmp",
        "/"
    ])
    func otherPaths_areNotTreatedAsCaches(path: String) {
        #expect(!Helpers.isRegenerableCachePath(URL(fileURLWithPath: path)))
    }

    // MARK: - isDatalessItem

    @Test func regularFileAndDirectory_areNotDataless() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("file.txt")
        try Data("hello".utf8).write(to: file)

        #expect(!Helpers.isDatalessItem(file))
        #expect(!Helpers.isDatalessItem(root))
    }

    @Test func missingPath_isNotDataless() {
        #expect(!Helpers.isDatalessItem(URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")))
    }

    @Test func danglingSymlink_isNotDataless() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/nonexistent/target")

        #expect(!Helpers.isDatalessItem(link))
    }

    // MARK: - Counting skips cache folders

    @Test func directoryCounters_ignoreCacheSubtrees() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let caches = root.appendingPathComponent("Library/Caches")
        let preferences = root.appendingPathComponent("Library/Preferences")
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: preferences, withIntermediateDirectories: true)
        try Data(count: 4096).write(to: caches.appendingPathComponent("cached.bin"))
        try Data("hello".utf8).write(to: preferences.appendingPathComponent("kept.plist"))

        // Items seen: Library, Preferences, kept.plist (Caches and what's inside are skipped).
        #expect(try await root.directoryTotalNumberOfFiles() == 3)
        #expect(Helpers.countFilesInDirectory(root) == 1)
        #expect(Helpers.calculateDirectorySize(root) == 5)
    }

    @Test func countersOnSkippedRoot_returnZero() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let caches = root.appendingPathComponent("Library/Caches")
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: caches.appendingPathComponent("cached.txt"))

        #expect(Helpers.shouldSkipForTransfer(caches))
        #expect(Helpers.countFilesInDirectory(caches) == 0)
        #expect(Helpers.calculateDirectorySize(caches) == 0)
    }

    // MARK: - Exclusion rules below the scanned levels

    @Test func descendantRule_appliesExtensionAndPrefixRules() {
        let base = URL(fileURLWithPath: "/Users/test/Projects/app/src/web")

        #expect(Helpers.shouldSkipDescendantForTransfer(base.appendingPathComponent("node_modules")))
        #expect(Helpers.shouldSkipDescendantForTransfer(base.appendingPathComponent(".DS_Store")))
        #expect(Helpers.shouldSkipDescendantForTransfer(base.appendingPathComponent("disk.vdi")))
        #expect(!Helpers.shouldSkipDescendantForTransfer(base.appendingPathComponent("index.html")))
    }

    @Test func descendantRule_doesNotUseCloudNameHeuristics() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // Ordinary folders that merely share a name with a sync provider's folder.
        for name in ["Box", "Sync", "MEGA", "Dropbox"] {
            let folder = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            #expect(!Helpers.shouldSkipDescendantForTransfer(folder))
        }
    }

    @Test func directoryCounters_ignoreDeeplyNestedExcludedItems() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let deep = root.appendingPathComponent("a/b/c/d", isDirectory: true)
        let modules = deep.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        try Data(count: 4096).write(to: modules.appendingPathComponent("dep.js"))
        try Data(count: 4096).write(to: deep.appendingPathComponent("disk.vdi"))
        try Data("hello".utf8).write(to: deep.appendingPathComponent("kept.txt"))

        // Items seen: a, b, c, d, kept.txt.
        #expect(try await root.directoryTotalNumberOfFiles() == 5)
        #expect(Helpers.countFilesInDirectory(root) == 1)
        #expect(Helpers.calculateDirectorySize(root) == 5)
    }

    // MARK: - Special files (named pipes)

    @Test func namedPipe_isSpecialAndSkipped() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pipe = root.appendingPathComponent("store.realm.note")
        #expect(mkfifo(pipe.path, 0o600) == 0)
        let file = root.appendingPathComponent("regular.txt")
        try Data("hello".utf8).write(to: file)

        #expect(Helpers.isSpecialFile(pipe))
        #expect(Helpers.shouldSkipForTransfer(pipe))
        #expect(!Helpers.isSpecialFile(file))
        #expect(!Helpers.isSpecialFile(root))
        #expect(!Helpers.shouldSkipForTransfer(file))
    }

    @Test func scanner_skipsNamedPipes_evenWhenExplicitlySelected() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pipe = root.appendingPathComponent("access_control.pick_writer.cv")
        #expect(mkfifo(pipe.path, 0o600) == 0)

        #expect(FileScanner.scan(url: pipe) == nil)
        #expect(FileScanner.scan(url: pipe, excludedItem: true) == nil)
    }

    @Test func directoryCounters_ignoreNamedPipes() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(mkfifo(root.appendingPathComponent("pipe.cv").path, 0o600) == 0)
        try Data("hello".utf8).write(to: root.appendingPathComponent("kept.txt"))

        // Only the regular file is counted when the pipe is a descendant that isn't inside a bundle.
        #expect(try await root.directoryTotalNumberOfFiles() == 1)
        #expect(Helpers.countFilesInDirectory(root) == 1)
    }

    // MARK: - Application bundles are copied whole

    @Test func insideAppBundle_nothingIsExcludedByName() {
        let figma = URL(fileURLWithPath: "/Applications/Figma.app/Contents/Resources/app.asar.unpacked")

        #expect(Helpers.isInsideAppBundle(figma.appendingPathComponent("node_modules")))
        #expect(!Helpers.shouldSkipDescendantForTransfer(figma.appendingPathComponent("node_modules")))
        #expect(!Helpers.shouldSkipDescendantForTransfer(figma.appendingPathComponent("disk.vdi")))
        #expect(!Helpers.isRegenerableCachePath(URL(fileURLWithPath: "/Applications/Foo.app/Contents/Library/Caches")))
        // The bundle itself is not "inside" one, so the name rules still apply to it.
        #expect(!Helpers.isInsideAppBundle(URL(fileURLWithPath: "/Applications/Safari.app")))
        #expect(Helpers.shouldSkipDescendantForTransfer(URL(fileURLWithPath: "/Applications/Safari.app")))
    }

    @Test func directoryCounters_keepNodeModulesInsideAppBundle() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Tool.app", isDirectory: true)
        let modules = bundle.appendingPathComponent("Contents/Resources/node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        try Data("dependency".utf8).write(to: modules.appendingPathComponent("dep.js"))

        // Items seen: Contents, Resources, node_modules, dep.js.
        #expect(try await bundle.directoryTotalNumberOfFiles() == 4)
        let totals = try #require(try await bundle.directoryAllocatedSizeAndItemCount())
        #expect(totals.count == 4)
    }

    // MARK: - Helpers

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
