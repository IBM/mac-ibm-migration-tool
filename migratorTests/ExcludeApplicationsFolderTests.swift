//
//  ExcludeApplicationsFolderTests.swift
//  migratorTests
//
//  Created by Simone Martorelli on 27/10/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import XCTest
@testable import Mac_IBM_Data_Shift

/// Tests for the `excludeApplicationsFolder` managed config key.
///
/// `Utils.UserDefaultsHelpers.registerManagedDefaults()` is called at app startup
/// (in `applicationWillFinishLaunching`) before any view body is evaluated, so both
/// `excludeApplicationsFolder` and `excludedPathsList` are already present in
/// `UserDefaults.standard.dictionaryRepresentation()` when
/// `Utils.UserDefaultsHelpers.customizedKeys` is first initialised. This means
/// `managedValue(forKey:)` correctly honours runtime writes to those keys throughout
/// the test run.
///
/// Every test is purely logic-level: only UserDefaults reads/writes and
/// `URL(fileURLWithPath:)` literals are used. No directory enumeration,
/// no `FileManager.default.urls(for:in:)` calls, and no `loadFiles()`
/// invocations occur, so the suite is safe to run in any CI environment
/// regardless of filesystem permissions.
final class ExcludeApplicationsFolderTests: XCTestCase {

    private static let excludeAppsFolderKey = "excludeApplicationsFolder"
    private static let excludedPathsListKey = "excludedPathsList"

    // Synthetic, stable paths used to exercise the `urlExclusionList` composition
    // rule without touching the real filesystem.
    private let mockLocalApps  = URL(fileURLWithPath: "/Applications")
    private let mockUserApps   = URL(fileURLWithPath: "/Users/testuser/Applications")
    private let mockSystemApps = URL(fileURLWithPath: "/System/Applications")

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: Self.excludeAppsFolderKey)
        UserDefaults.standard.removeObject(forKey: Self.excludedPathsListKey)
    }

    // MARK: - shouldExcludeApplicationsFolder default & toggle

    /// When the key is absent the flag must default to `false`.
    func testShouldExcludeApplicationsFolder_DefaultIsFalse() {
        XCTAssertFalse(AppContext.shouldExcludeApplicationsFolder,
                       "shouldExcludeApplicationsFolder must default to false when the key is absent")
    }

    /// Setting the key to `true` must be reflected immediately.
    func testShouldExcludeApplicationsFolder_TrueWhenKeyIsTrue() {
        UserDefaults.standard.set(true, forKey: Self.excludeAppsFolderKey)
        XCTAssertTrue(AppContext.shouldExcludeApplicationsFolder,
                      "shouldExcludeApplicationsFolder must be true when the defaults key is true")
    }

    /// Setting the key to `false` must be reflected immediately.
    func testShouldExcludeApplicationsFolder_FalseWhenKeyIsFalse() {
        UserDefaults.standard.set(false, forKey: Self.excludeAppsFolderKey)
        XCTAssertFalse(AppContext.shouldExcludeApplicationsFolder,
                       "shouldExcludeApplicationsFolder must be false when the defaults key is false")
    }

    // MARK: - urlExclusionList composition

    /// Paths injected through `excludedPathsList` must appear in `urlExclusionList`
    /// regardless of the `excludeApplicationsFolder` flag — the two channels are independent.
    func testUrlExclusionList_ManagedPathsPresent_WhenFlagIsFalse() {
        let mockPaths = [mockLocalApps.path, mockUserApps.path, mockSystemApps.path]
        UserDefaults.standard.set(mockPaths, forKey: Self.excludedPathsListKey)
        UserDefaults.standard.set(false, forKey: Self.excludeAppsFolderKey)

        let exclusionPaths = AppContext.urlExclusionList.compactMap { $0?.standardizedFileURL.path }

        for path in mockPaths {
            XCTAssertTrue(exclusionPaths.contains(URL(fileURLWithPath: path).standardizedFileURL.path),
                          "urlExclusionList must include '\(path)' injected via excludedPathsList (flag=false)")
        }
    }

    /// Same paths must also be present when the flag is `true`.
    func testUrlExclusionList_ManagedPathsPresent_WhenFlagIsTrue() {
        let mockPaths = [mockLocalApps.path, mockUserApps.path, mockSystemApps.path]
        UserDefaults.standard.set(mockPaths, forKey: Self.excludedPathsListKey)
        UserDefaults.standard.set(true, forKey: Self.excludeAppsFolderKey)

        let exclusionPaths = AppContext.urlExclusionList.compactMap { $0?.standardizedFileURL.path }

        for path in mockPaths {
            XCTAssertTrue(exclusionPaths.contains(URL(fileURLWithPath: path).standardizedFileURL.path),
                          "urlExclusionList must include '\(path)' injected via excludedPathsList (flag=true)")
        }
    }

    /// Enabling the flag must produce a list at least as long as disabling it, because
    /// `allApplicationsFolderURLs` is prepended. Both measurements use the same empty
    /// `excludedPathsList` so the only variable is the flag itself.
    func testUrlExclusionList_FlagTrue_ProducesListAtLeastAsLongAsFlagFalse() {
        UserDefaults.standard.set(true, forKey: Self.excludeAppsFolderKey)
        let countWithFlagOn = AppContext.urlExclusionList.count

        UserDefaults.standard.set(false, forKey: Self.excludeAppsFolderKey)
        let countWithFlagOff = AppContext.urlExclusionList.count

        XCTAssertGreaterThanOrEqual(countWithFlagOn, countWithFlagOff,
                                    "urlExclusionList must not shrink when excludeApplicationsFolder switches from false to true")
    }

    /// When the flag is `false` and `excludedPathsList` is empty, the list length must equal
    /// the length with the key absent — the flag alone must not add anything.
    func testUrlExclusionList_FlagFalse_LengthEqualsAbsent() {
        UserDefaults.standard.set(false, forKey: Self.excludeAppsFolderKey)
        let withFlagFalse = AppContext.urlExclusionList.count

        UserDefaults.standard.removeObject(forKey: Self.excludeAppsFolderKey)
        let withKeyAbsent = AppContext.urlExclusionList.count

        XCTAssertEqual(withFlagFalse, withKeyAbsent,
                       "urlExclusionList must have the same count when the flag is false as when the key is absent")
    }
}
