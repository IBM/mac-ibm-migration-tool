//
//  PreferenceCatalogTests.swift
//  migratorTests
//
//  Created by Simone Martorelli on 01/10/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import XCTest
@testable import Mac_IBM_Data_Shift

final class PreferenceCatalogTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    // MARK: - Catalog Integrity Tests

    /// Test that every catalog item has a unique identifier.
    func testCatalog_HasUniqueIDs() throws {
        let ids = PreferenceCatalog.allItems.map { $0.id }
        XCTAssertEqual(ids.count, Set(ids).count, "Catalog items must have unique identifiers")
    }

    /// Test that every catalog item has at least one domain.
    func testCatalog_EveryItemHasAtLeastOneDomain() throws {
        for item in PreferenceCatalog.allItems {
            XCTAssertFalse(item.domains.isEmpty, "\(item.id) should declare at least one domain")
        }
    }

    /// Test that every catalog item's name and setting description keys resolve to a localized value
    /// (i.e. are present in the string catalog, rather than falling back to the raw key).
    func testCatalog_LocalizationKeysResolve() throws {
        for item in PreferenceCatalog.allItems {
            XCTAssertNotEqual(item.nameKey.localized, item.nameKey, "\(item.nameKey) is missing from the string catalog")
            for settingKey in item.settingDescriptionKeys {
                XCTAssertNotEqual(settingKey.localized, settingKey, "\(settingKey) is missing from the string catalog")
            }
        }
    }

    /// Test that every catalog item declares at least one human-readable setting description.
    func testCatalog_EveryItemHasSettingDescriptions() throws {
        for item in PreferenceCatalog.allItems {
            XCTAssertFalse(item.settingDescriptionKeys.isEmpty, "\(item.id) should describe at least one setting")
        }
    }

    // MARK: - PreferenceDomain.filter Tests

    /// Test that `.only` keeps exactly the listed keys.
    func testDomainFilter_OnlyKeepsListedKeys() throws {
        let domain = PreferenceDomain(applicationID: "com.apple.dock", keyFilter: .only(["autohide", "tilesize"]))
        let filtered = domain.filter(["autohide": true, "tilesize": 48, "mod-count": 3])

        XCTAssertEqual(filtered.count, 2)
        XCTAssertNotNil(filtered["autohide"])
        XCTAssertNotNil(filtered["tilesize"])
        XCTAssertNil(filtered["mod-count"])
    }

    /// Test that `.allExcept` removes exactly the listed keys and keeps the rest.
    func testDomainFilter_AllExceptRemovesListedKeys() throws {
        let domain = PreferenceDomain(applicationID: "com.apple.finder", keyFilter: .allExcept(["FXRecentFolders"]))
        let filtered = domain.filter(["FXRecentFolders": ["a"], "ShowPathbar": true])

        XCTAssertNil(filtered["FXRecentFolders"])
        XCTAssertNotNil(filtered["ShowPathbar"])
    }

    /// Test that `.prefixes` keeps only keys starting with one of the given prefixes.
    func testDomainFilter_PrefixesKeepsMatchingKeys() throws {
        let domain = PreferenceDomain(applicationID: "com.apple.dock", keyFilter: .prefixes(["wvous-tl"]))
        let filtered = domain.filter(["wvous-tl-corner": 4, "wvous-tr-corner": 2, "autohide": false])

        XCTAssertEqual(filtered.count, 1)
        XCTAssertNotNil(filtered["wvous-tl-corner"])
    }

    /// Test that `.all` keeps every key.
    func testDomainFilter_AllKeepsEveryKey() throws {
        let domain = PreferenceDomain(applicationID: "com.apple.screencapture", keyFilter: .all)
        let values: [String: Any] = ["location": "~/Desktop", "type": "png"]
        let filtered = domain.filter(values)

        XCTAssertEqual(filtered.count, values.count)
    }

    /// Test that transient window/navigation keys are dropped regardless of the key filter used.
    func testDomainFilter_DropsTransientKeysRegardlessOfFilter() throws {
        let domain = PreferenceDomain(applicationID: "com.apple.finder", keyFilter: .all)
        let filtered = domain.filter(["NSWindow Frame MainWindow": "0 0 100 100",
                                      "NSSplitView Subview Frames NSSplitView": [],
                                      "NSNavPanelExpandedStateForSaveMode": true,
                                      "ShowPathbar": true])

        XCTAssertEqual(filtered.count, 1)
        XCTAssertNotNil(filtered["ShowPathbar"])
    }

    // MARK: - PreferencesMessage Tests

    /// Test that `PreferencesMessage` survives a JSON encode/decode round trip, including a nil applicationID.
    func testPreferencesMessage_RoundTrips() throws {
        let message = PreferencesMessage(groupID: "dock", applicationID: "com.apple.dock", isByHost: false)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(PreferencesMessage.self, from: data)

        XCTAssertEqual(decoded.groupID, message.groupID)
        XCTAssertEqual(decoded.applicationID, message.applicationID)
        XCTAssertEqual(decoded.isByHost, message.isByHost)
    }

    /// Test that a global-domain message (nil applicationID) round trips correctly.
    func testPreferencesMessage_RoundTripsWithNilApplicationID() throws {
        let message = PreferencesMessage(groupID: "appearance", applicationID: nil, isByHost: false)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(PreferencesMessage.self, from: data)

        XCTAssertNil(decoded.applicationID)
        XCTAssertEqual(decoded.groupID, message.groupID)
    }
}
