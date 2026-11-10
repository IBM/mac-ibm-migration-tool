//
//  EphemeralTLSIdentityTests.swift
//  migratorTests
//
//  Created by Simone Martorelli on 25/09/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import XCTest
import Security
@testable import Mac_IBM_Data_Shift

final class EphemeralTLSIdentityTests: XCTestCase {

    func testMakeIdentitySucceedsAndStaysOutOfKeychain() throws {
        let identity = try EphemeralTLSIdentity.makeIdentity()
        XCTAssertNotNil(identity)

        // A blanket kSecClassIdentity query would also match identities unrelated to this app
        // (VPN profiles, developer certs, etc. that most Macs already have), so search
        // specifically for the ephemeral certificate's well-known common name.
        let query: [CFString: Any] = [
            kSecClass: kSecClassIdentity,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecMatchSubjectContains: "Data Shift Pairing",
            kSecReturnRef: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        XCTAssertTrue(status == errSecItemNotFound || (result as? [Any])?.isEmpty == true,
                      "The ephemeral identity must never be persisted to any keychain, got status \(status)")
    }

    func testMakeIdentityCanBeCalledRepeatedly() throws {
        _ = try EphemeralTLSIdentity.makeIdentity()
        _ = try EphemeralTLSIdentity.makeIdentity()
    }
}
