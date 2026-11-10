//
//  PreferencesDiscovery.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 01/10/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// Reads and writes macOS preference values on behalf of the `PreferenceCatalog`, using `CFPreferences`
/// rather than copying `.plist` files directly, so values survive `cfprefsd`'s in-memory cache.
struct PreferencesDiscovery {

    // MARK: - Private Constants

    private static let logger = MLogger.main.scoped(to: .migration)

    /// `CFPreferences` application ID representing the global domain (`.GlobalPreferences.plist`).
    private static let globalApplicationID = kCFPreferencesAnyApplication as String

    // MARK: - Public Methods

    /// Discovers which catalog groups have at least one preference value on this Mac.
    /// - Returns: A `PreferenceGroup` for every catalog item that has discovered values, in catalog order.
    static func discoverAvailableGroups() async -> [PreferenceGroup] {
        let discovered: [(item: PreferenceCatalogItem, values: [PreferenceDomain: Data])] = await Task.detached(priority: .utility) {
            PreferenceCatalog.allItems.compactMap { item -> (item: PreferenceCatalogItem, values: [PreferenceDomain: Data])? in
                var discovered: [PreferenceDomain: Data] = [:]
                for domain in item.domains {
                    let values = domain.filter(readValues(for: domain))
                    guard !values.isEmpty,
                          let data = try? PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0) else { continue }
                    discovered[domain] = data
                }
                guard !discovered.isEmpty else { return nil }
                return (item, discovered)
            }
        }.value
        // `PreferenceGroup` is main-actor-isolated (it's `@Published`-backed), so construction
        // happens here rather than inside the detached task above.
        var groups: [PreferenceGroup] = []
        groups.reserveCapacity(discovered.count)
        for entry in discovered {
            groups.append(await PreferenceGroup(catalogItem: entry.item, discoveredValues: entry.values))
        }
        return groups
    }

    /// Reads and serializes the current values for a group's domains, ready to send. Values are re-read
    /// at call time rather than reusing `group.discoveredValues`, so nothing goes stale between discovery and sending.
    /// - Parameter group: The preference group being migrated.
    /// - Returns: One binary plist payload per domain that still has values on this Mac.
    static func payloads(for group: PreferenceGroup) -> [(domain: PreferenceDomain, data: Data)] {
        return group.catalogItem.domains.compactMap { domain -> (domain: PreferenceDomain, data: Data)? in
            let values = domain.filter(readValues(for: domain))
            guard !values.isEmpty,
                  let data = try? PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0) else {
                return nil
            }
            return (domain, data)
        }
    }

    /// Reads every current value for a domain.
    /// - Parameter domain: The domain to read.
    /// - Returns: The domain's raw values, unfiltered.
    static func readValues(for domain: PreferenceDomain) -> [String: Any] {
        let appID = (domain.applicationID ?? globalApplicationID) as CFString
        let hostName = domain.isByHost ? kCFPreferencesCurrentHost : kCFPreferencesAnyHost
        guard let result = CFPreferencesCopyMultiple(nil, appID, kCFPreferencesCurrentUser, hostName) as? [String: Any] else {
            return [:]
        }
        return result
    }

    /// Writes a domain's values to this Mac's preferences, after backing up its current values.
    /// - Parameters:
    ///   - data: The binary plist payload received from the source Mac.
    ///   - domain: The domain to write to.
    /// - Throws: `MigratorError.fileError` if the payload can't be deserialized.
    static func apply(_ data: Data, to domain: PreferenceDomain) throws {
        guard let values = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw MigratorError.fileError(type: .noData)
        }
        let domainName = domain.applicationID ?? "global"
        logger.log("preferencesDiscovery.apply: applying \(values.count) value(s) to domain \"\(domainName)\"")
        backup(domain: domain)
        let appID = (domain.applicationID ?? globalApplicationID) as CFString
        let hostName = domain.isByHost ? kCFPreferencesCurrentHost : kCFPreferencesAnyHost
        for (key, value) in values {
            CFPreferencesSetValue(key as CFString, value as AnyObject, appID, kCFPreferencesCurrentUser, hostName)
        }
        guard CFPreferencesSynchronize(appID, kCFPreferencesCurrentUser, hostName) else {
            logger.log("preferencesDiscovery.apply: failed to synchronize domain \"\(domainName)\"", type: .error)
            return
        }
        logger.log("preferencesDiscovery.apply: domain \"\(domainName)\" applied and synchronized")
    }

    // MARK: - Private Methods

    /// Backs up a domain's current values to the migration backup folder before overwriting them.
    private static func backup(domain: PreferenceDomain) {
        let currentValues = readValues(for: domain)
        guard !currentValues.isEmpty,
              let data = try? PropertyListSerialization.data(fromPropertyList: currentValues, format: .binary, options: 0) else { return }
        let domainName = domain.applicationID ?? "GlobalPreferences"
        let backupFolder = "\(AppContext.backupPath)/Preferences"
        if !FileManager.default.fileExists(atPath: backupFolder) {
            try? FileManager.default.createDirectory(atPath: backupFolder, withIntermediateDirectories: true)
        }
        do {
            let backupURL = URL(fileURLWithPath: "\(backupFolder)/\(domainName)\(domain.isByHost ? ".byhost" : "").plist")
            try data.write(to: backupURL)
            logger.log("preferencesDiscovery.backup: backed up domain \"\(domainName)\" to \"\(backupURL.relativePath)\"")
        } catch {
            logger.log("preferencesDiscovery.backup: failed to back up domain \"\(domainName)\" -> \"\(error.localizedDescription)\"", type: .error)
        }
    }
}
