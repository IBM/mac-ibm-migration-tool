//
//  MigrationPresetTests.swift
//  migratorTests
//
//  Created by Simone Martorelli on 07/10/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import XCTest
@testable import Mac_IBM_Data_Shift

final class MigrationPresetTests: XCTestCase {

    // MARK: - Decoding Tests

    /// A fully-specified dictionary (as an admin might author in a configuration profile)
    /// should decode every field as given.
    func testDecode_FullDictionary() throws {
        let dictionary: [String: Any] = [
            "id": "projects",
            "name": "Projects Only",
            "categories": ["desktop", "apps"],
            "additionalPaths": ["$HOMEFOLDER/Projects"]
        ]

        let preset = try DictionaryDecoder().decode(MigrationPreset.self, from: dictionary)

        XCTAssertEqual(preset.id, "projects")
        XCTAssertEqual(preset.name, "Projects Only")
        XCTAssertEqual(preset.categories, [.desktop, .apps])
        XCTAssertEqual(preset.additionalPaths, ["$HOMEFOLDER/Projects"])
    }

    /// Admins should only need to specify the keys that matter to them: `categories` and
    /// `additionalPaths` both default to empty.
    func testDecode_MinimalDictionaryAppliesDefaults() throws {
        let dictionary: [String: Any] = [
            "id": "minimal",
            "name": "Minimal Preset"
        ]

        let preset = try DictionaryDecoder().decode(MigrationPreset.self, from: dictionary)

        XCTAssertEqual(preset.id, "minimal")
        XCTAssertEqual(preset.name, "Minimal Preset")
        XCTAssertTrue(preset.categories.isEmpty)
        XCTAssertTrue(preset.additionalPaths.isEmpty)
    }

    /// An unrecognised category name (typo, or a newer category used against an older app build)
    /// is dropped individually rather than failing decoding of the whole preset.
    func testDecode_UnrecognisedCategoryIsDroppedIndividually() throws {
        let dictionary: [String: Any] = [
            "id": "typo",
            "name": "Typo Preset",
            "categories": ["desktop", "dcouments", "apps"]
        ]

        let preset = try DictionaryDecoder().decode(MigrationPreset.self, from: dictionary)

        XCTAssertEqual(preset.categories, [.desktop, .apps])
    }

    /// A dictionary missing a required field (`id`) is malformed and must fail to decode, so
    /// callers like `AppContext.migrationPresets` can drop it via `try?`.
    func testDecode_MissingRequiredFieldThrows() throws {
        let dictionary: [String: Any] = [
            "name": "No Id"
        ]

        XCTAssertThrowsError(try DictionaryDecoder().decode(MigrationPreset.self, from: dictionary))
    }

    /// A dictionary missing the required `name` field must also fail to decode.
    func testDecode_MissingNameThrows() throws {
        let dictionary: [String: Any] = [
            "id": "no-name"
        ]

        XCTAssertThrowsError(try DictionaryDecoder().decode(MigrationPreset.self, from: dictionary))
    }

    // MARK: - Built-in Preset Tests

    /// The built-in `.lite` preset must preserve the historical `Lite` migration option behavior:
    /// Desktop and Documents only.
    func testBuiltInLitePreset_MatchesHistoricalBehavior() {
        let preset = MigrationPreset.lite

        XCTAssertEqual(preset.id, "lite")
        XCTAssertEqual(preset.categories, [.desktop, .documents])
        XCTAssertTrue(preset.additionalPaths.isEmpty)
    }

    /// The built-in `.complete` preset must preserve the historical `Complete` migration option
    /// behavior: the whole user folder, apps, and preferences.
    func testBuiltInCompletePreset_MatchesHistoricalBehavior() {
        let preset = MigrationPreset.complete

        XCTAssertEqual(preset.id, "complete")
        XCTAssertEqual(preset.categories, [.userFolder, .apps, .preferences])
        XCTAssertTrue(preset.additionalPaths.isEmpty)
    }

    // MARK: - Hashable/Equatable Tests

    /// Presets are used as SwiftUI picker tags and dictionary keys, so equal presets must hash
    /// equally and distinct `id`s must not collide.
    func testEquatableAndHashable_DistinguishById() {
        let presetA = MigrationPreset(id: "a", name: "A")
        let presetB = MigrationPreset(id: "b", name: "A")
        let presetADuplicate = MigrationPreset(id: "a", name: "A")

        XCTAssertEqual(presetA, presetADuplicate)
        XCTAssertNotEqual(presetA, presetB)
        XCTAssertEqual(Set([presetA, presetADuplicate]).count, 1)
    }
}
