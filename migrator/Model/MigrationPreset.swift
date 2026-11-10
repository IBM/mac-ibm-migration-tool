//
//  MigrationPreset.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 07/10/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// Represents a "standard" migration preset: a named bundle of well-known categories to migrate.
/// `Lite` and `Complete` are the built-in presets; an admin can replace them entirely with their
/// own set via the `migrationPresets` managed setting (see `AppContext.migrationPresets`).
struct MigrationPreset: Codable, Hashable, Sendable {

    /// A well-known migration category a preset can opt into. Adding a new standard category is a
    /// single new case here plus one new arm in the `switch` that resolves it (`MigrationOption.loadFiles()`
    /// for path-based categories, or a `.contains` check where the category is resolved elsewhere,
    /// e.g. `.preferences` in `MigrationOption.discoverPreferences()`) - the preset's shape and its
    /// decoding never need to change.
    enum Category: String, Codable, Hashable, CaseIterable, Sendable {
        /// The user's Desktop folder.
        case desktop
        /// The user's Documents folder.
        case documents
        /// The entire home folder. Supersedes `desktop`, `documents` and `additionalPaths`, since
        /// all of them are already contained within it.
        case userFolder
        /// Applications discovered in the `/Applications` folder.
        case apps
        /// macOS preferences, discovered via `PreferencesDiscovery`.
        case preferences
    }

    // MARK: - Variables

    /// Stable identifier for the preset. Used for `Hashable`/`Equatable` conformance, as the
    /// SwiftUI picker tag, and recorded in the migration report as the chosen option.
    var id: String
    /// Display name shown in the picker, matching how `Lite`/`Complete` are shown today (not localized).
    var name: String
    /// The categories this preset migrates.
    var categories: Set<Category>
    /// Additional paths to migrate, written using the same `$HOMEFOLDER`/`$APPFOLDER` placeholder
    /// syntax supported by `Utils.Customization.parseProfileURL(_:)`.
    var additionalPaths: [String]

    // MARK: - Initializers

    init(id: String, name: String, categories: Set<Category> = [], additionalPaths: [String] = []) {
        self.id = id
        self.name = name
        self.categories = categories
        self.additionalPaths = additionalPaths
    }

    /// Admin-authored presets only need to specify the keys that matter to them: `categories` and
    /// `additionalPaths` both default to empty. An unrecognised category name (e.g. a typo, or a
    /// name introduced by a newer app version and used in a profile pushed to an older one) is
    /// dropped individually rather than failing the whole preset.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        self.id = id
        self.name = try container.decode(String.self, forKey: .name)
        let rawCategories = try container.decodeIfPresent([String].self, forKey: .categories) ?? []
        self.categories = Set(rawCategories.compactMap { rawCategory -> Category? in
            guard let category = Category(rawValue: rawCategory) else {
                MLogger.main.log("migrationPreset.init: dropping unrecognised category \"\(rawCategory)\" for preset \"\(id)\"")
                return nil
            }
            return category
        })
        self.additionalPaths = try container.decodeIfPresent([String].self, forKey: .additionalPaths) ?? []
    }

    // MARK: - Built-in Presets

    /// Built-in preset matching the historical `Lite` migration option: Desktop and Documents only.
    static let lite = MigrationPreset(id: "lite", name: "Lite", categories: [.desktop, .documents])

    /// Built-in preset matching the historical `Complete` migration option: the whole user folder,
    /// installed applications, and macOS preferences.
    static let complete = MigrationPreset(id: "complete", name: "Complete", categories: [.userFolder, .apps, .preferences])
}
