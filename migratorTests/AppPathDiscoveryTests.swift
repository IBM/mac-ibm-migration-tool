//
//  AppPathDiscoveryTests.swift
//  migratorTests
//
//  Created by Simone Martorelli on 01/10/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import XCTest
@testable import Mac_IBM_Data_Shift

@MainActor
final class AppPathDiscoveryTests: XCTestCase {

    // XCTest guarantees setUp/test/tearDown run serially for a given instance, so this is never
    // actually touched concurrently despite the class being `@MainActor`.
    nonisolated(unsafe) var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Create a temporary directory for testing
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Clean up temporary directory
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        try super.tearDownWithError()
    }

    // MARK: - String Extension Tests

    func testNormalize_RemovesSpaces() throws {
        XCTAssertEqual("My Test App".normalize(), "mytestapp")
    }

    func testNormalize_RemovesHyphens() throws {
        XCTAssertEqual("My-Test-App".normalize(), "mytestapp")
    }

    func testNormalize_RemovesUnderscores() throws {
        XCTAssertEqual("My_Test_App".normalize(), "mytestapp")
    }

    func testNormalize_HandlesEmptyString() throws {
        XCTAssertEqual("".normalize(), "")
    }

    func testNormalize_HandlesMixedCharacters() throws {
        XCTAssertEqual("My-Test_App Name".normalize(), "mytestappname")
    }

    // MARK: - AppInfo Tests

    func testAppInfo_Initialization() throws {
        let appInfo = AppInfo(bundleIdentifier: "com.test.app",
                               appName: "TestApp",
                               path: URL(fileURLWithPath: "/Applications/TestApp.app"))

        XCTAssertEqual(appInfo.appName, "TestApp")
        XCTAssertEqual(appInfo.bundleIdentifier, "com.test.app")
        XCTAssertTrue(appInfo.applicationSupportFiles.isEmpty)
        XCTAssertTrue(appInfo.containerFiles.isEmpty)
        XCTAssertTrue(appInfo.groupContainerFiles.isEmpty)
        XCTAssertTrue(appInfo.preferenceFiles.isEmpty)
    }

    func testAppInfo_AllDiscoveredPaths() throws {
        let appInfo = AppInfo(bundleIdentifier: "com.test.app",
                               appName: "TestApp",
                               path: URL(fileURLWithPath: "/Applications/TestApp.app"))

        let url1 = URL(fileURLWithPath: "/path1")
        let url2 = URL(fileURLWithPath: "/path2")
        let url3 = URL(fileURLWithPath: "/path3")

        appInfo.applicationSupportFiles.insert(url1)
        appInfo.containerFiles.insert(url2)
        appInfo.preferenceFiles.insert(url3)

        let allPaths = appInfo.allDiscoveredPaths
        XCTAssertEqual(allPaths.count, 3)
        XCTAssertTrue(allPaths.contains(url1))
        XCTAssertTrue(allPaths.contains(url2))
        XCTAssertTrue(allPaths.contains(url3))
    }

    func testAppInfo_DiscoveredFileCount() throws {
        let appInfo = AppInfo(bundleIdentifier: "com.test.app",
                               appName: "TestApp",
                               path: URL(fileURLWithPath: "/Applications/TestApp.app"))

        XCTAssertEqual(appInfo.discoveredFileCount, 0)

        appInfo.applicationSupportFiles.insert(URL(fileURLWithPath: "/path1"))
        XCTAssertEqual(appInfo.discoveredFileCount, 1)

        appInfo.containerFiles.insert(URL(fileURLWithPath: "/path2"))
        XCTAssertEqual(appInfo.discoveredFileCount, 2)
    }

    func testAppInfo_TotalSize() async throws {
        let appInfo = AppInfo(bundleIdentifier: "com.test.app",
                               appName: "TestApp",
                               path: tempDirectory)

        // Create test files
        let file1 = tempDirectory.appendingPathComponent("file1.txt")
        let file2 = tempDirectory.appendingPathComponent("file2.txt")

        try Data(count: 1024).write(to: file1)
        try Data(count: 2048).write(to: file2)

        appInfo.applicationSupportFiles.insert(file1)
        appInfo.containerFiles.insert(file2)

        let totalSize = await appInfo.getTotalSize()
        XCTAssertGreaterThan(totalSize, 0)
    }

    // MARK: - FileSizeCache Tests

    func testFileSizeCache_Singleton() throws {
        let cache1 = FileSizeCache.shared
        let cache2 = FileSizeCache.shared

        XCTAssertTrue(cache1 === cache2)
    }

    func testFileSizeCache_CachesSize() throws {
        let cache = FileSizeCache.shared

        let testFile = tempDirectory.appendingPathComponent("test.txt")
        try Data(count: 1024).write(to: testFile)

        cache.setCachedSize(for: testFile, size: 1024, numberOfFiles: 1)
        let cached = cache.getCachedSize(for: testFile)

        XCTAssertEqual(cached?.size, 1024)
        XCTAssertEqual(cached?.numberOfFiles, 1)
    }

    func testFileSizeCache_HandlesNonExistentFile() throws {
        let cache = FileSizeCache.shared
        let nonExistent = tempDirectory.appendingPathComponent("nonexistent.txt")

        XCTAssertNil(cache.getCachedSize(for: nonExistent))
    }

    func testFileSizeCache_ClearCache() throws {
        let cache = FileSizeCache.shared

        let testFile = tempDirectory.appendingPathComponent("test.txt")
        try Data(count: 1024).write(to: testFile)

        cache.setCachedSize(for: testFile, size: 1024, numberOfFiles: 1)
        cache.clearCache()

        XCTAssertNil(cache.getCachedSize(for: testFile))
    }

    // MARK: - DiscoveredApplication Tests

    func testDiscoveredApplication_TotalSizeWithAppInfo() async throws {
        let appURL = tempDirectory.appendingPathComponent("TestApp.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

        let migratorFile = await MigratorFile.make(with: appURL)!
        let app = DiscoveredApplication(from: migratorFile, architectures: [])!

        let appOnlySize = await app.getTotalSizeAsync()

        let appInfo = AppInfo(bundleIdentifier: "com.test.app", appName: "TestApp", path: appURL)

        let supportFile = tempDirectory.appendingPathComponent("support.txt")
        try Data(count: 5000).write(to: supportFile)
        appInfo.applicationSupportFiles.insert(supportFile)

        app.appInfo = appInfo

        let totalSize = await app.getTotalSizeAsync()
        XCTAssertGreaterThan(totalSize, appOnlySize)
    }

    func testDiscoveredApplication_HasSupportFiles() async throws {
        let appURL = tempDirectory.appendingPathComponent("TestApp.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

        let migratorFile = await MigratorFile.make(with: appURL)!
        let app = DiscoveredApplication(from: migratorFile, architectures: [])!

        XCTAssertEqual(app.supportFileCount, 0)

        let appInfo = AppInfo(bundleIdentifier: "com.test.app", appName: "TestApp", path: appURL)
        appInfo.applicationSupportFiles.insert(URL(fileURLWithPath: "/path"))
        app.appInfo = appInfo

        XCTAssertGreaterThan(app.supportFileCount, 0)
    }
}
