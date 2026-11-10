//
//  PairingAuthenticatorTests.swift
//  migratorTests
//
//  Created by Simone Martorelli on 25/09/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import XCTest
import CryptoKit
@testable import Mac_IBM_Data_Shift

final class PairingAuthenticatorTests: XCTestCase {

    private let channelBinding = Data("test-channel-binding".utf8)
    private let context = "test-build-identity"

    private func run(passcode: String,
                     clientPasscode: String? = nil,
                     clientChannelBinding: Data? = nil) throws -> (client: PairingAuthenticator, server: PairingAuthenticator) {
        var client = try PairingAuthenticator(role: .client, passcode: clientPasscode ?? passcode,
                                               channelBinding: clientChannelBinding ?? channelBinding, context: context)
        var server = try PairingAuthenticator(role: .server, passcode: passcode,
                                               channelBinding: channelBinding, context: context)

        let clientShare = try client.makeShare()
        let serverShare = try server.makeShare()

        try client.deriveKeys(peerShare: serverShare)
        try server.deriveKeys(peerShare: clientShare)

        return (client, server)
    }

    func testMatchingPasscodeProducesEqualSessionKeysAndValidConfirmations() throws {
        let (client, server) = try run(passcode: "123456")

        let clientKey = try XCTUnwrap(client.sessionKey)
        let serverKey = try XCTUnwrap(server.sessionKey)
        XCTAssertEqual(clientKey.withUnsafeBytes { Data($0) }, serverKey.withUnsafeBytes { Data($0) })

        let serverConfirmation = try server.confirmation()
        let clientConfirmation = try client.confirmation()
        XCTAssertNoThrow(try client.verify(peerConfirmation: serverConfirmation))
        XCTAssertNoThrow(try server.verify(peerConfirmation: clientConfirmation))
    }

    func testWrongPasscodeFailsConfirmation() throws {
        let (client, server) = try run(passcode: "654321", clientPasscode: "111111")

        let serverConfirmation = try server.confirmation()
        XCTAssertThrowsError(try client.verify(peerConfirmation: serverConfirmation)) { error in
            XCTAssertEqual(error as? PairingAuthenticator.PairingError, .confirmationMismatch)
        }
    }

    func testDifferentChannelBindingFailsConfirmation() throws {
        // Simulates an active man-in-the-middle terminating its own TLS session with each side:
        // both sides use the correct passcode, but each sees a different TLS exporter value.
        let (client, server) = try run(passcode: "123456", clientChannelBinding: Data("different-channel".utf8))

        let serverConfirmation = try server.confirmation()
        XCTAssertThrowsError(try client.verify(peerConfirmation: serverConfirmation)) { error in
            XCTAssertEqual(error as? PairingAuthenticator.PairingError, .confirmationMismatch)
        }
    }

    func testInvalidPeerShareThrows() throws {
        var client = try PairingAuthenticator(role: .client, passcode: "123456", channelBinding: channelBinding, context: context)

        XCTAssertThrowsError(try client.deriveKeys(peerShare: Data(repeating: 0xFF, count: 32))) { error in
            XCTAssertEqual(error as? PairingAuthenticator.PairingError, .invalidPeerShare)
        }
        XCTAssertThrowsError(try client.deriveKeys(peerShare: Data(repeating: 0x01, count: 16))) { error in
            XCTAssertEqual(error as? PairingAuthenticator.PairingError, .invalidPeerShare)
        }
    }

    func testConfirmationBeforeDeriveKeysThrowsProtocolViolation() throws {
        var client = try PairingAuthenticator(role: .client, passcode: "123456", channelBinding: channelBinding, context: context)
        _ = try client.makeShare()

        XCTAssertThrowsError(try client.confirmation()) { error in
            XCTAssertEqual(error as? PairingAuthenticator.PairingError, .protocolViolation)
        }
    }

    func testHashToCurveIsDeterministic() throws {
        // Two independent authenticators built from the same inputs must derive the same base
        // point, since both sides compute it locally rather than exchanging it over the wire.
        // Using the same fixed scalar on both isolates that: if the generators match, the
        // resulting shares (X(scalar·G)) must match too.
        let fixedScalar = P256.KeyAgreement.PrivateKey()
        var first = try PairingAuthenticator(role: .client, passcode: "999999", channelBinding: channelBinding, context: context,
                                              ephemeralPrivateKey: fixedScalar)
        var second = try PairingAuthenticator(role: .client, passcode: "999999", channelBinding: channelBinding, context: context,
                                               ephemeralPrivateKey: fixedScalar)

        XCTAssertEqual(try first.makeShare(), try second.makeShare())
    }
}
