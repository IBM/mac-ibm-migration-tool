//
//  PairingAuthenticator.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 25/09/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation
import CryptoKit

/// Which side of the pairing exchange this authenticator is running.
enum PairingRole {
    case client
    case server
}

/// A CPace-style password-authenticated key exchange (PAKE) run over an already-established
/// TLS 1.3 channel, bound to that channel via its exporter secret.
///
/// TLS 1.3 removed Network.framework's external-PSK mode, so the 6-digit pairing code can no
/// longer gate the TLS handshake itself. Instead the destination Mac serves an ephemeral,
/// unauthenticated TLS certificate (see `EphemeralTLSIdentity`) purely for confidentiality and
/// forward secrecy, and this type checks the code at the application layer immediately after
/// the handshake completes. Binding the exchange to the TLS exporter secret means a
/// man-in-the-middle that terminates its own TLS session with each side (and so sees a
/// different exporter value on each side) cannot relay pairing messages between them and pass
/// as a legitimate participant, even though it holds valid TLS certificates for both legs.
///
/// Both sides derive the same base point `G` locally from the passcode, channel binding, and
/// build identity (see `hashToCurve`), so `G` itself is never sent over the wire. Only shares
/// (x-coordinates of ephemeral-scalar multiples of `G`) are exchanged; reconstructing a point
/// from a bare x-coordinate is inherently sign-ambiguous, but that ambiguity cancels out in the
/// final key because negating a point never changes its x-coordinate. This is standard practice
/// for x-coordinate-only Diffie-Hellman schemes and requires no explicit tracking of point signs.
struct PairingAuthenticator {

    enum PairingError: Error, Equatable {
        case hashToCurveFailed
        case invalidPeerShare
        case confirmationMismatch
        case protocolViolation
    }

    let role: PairingRole

    private let channelBinding: Data
    private let generatorPoint: P256.KeyAgreement.PublicKey
    private let ephemeralPrivateKey: P256.KeyAgreement.PrivateKey

    private var myShare: Data?
    private var peerShare: Data?
    private var interimSymmetricKey: SymmetricKey?

    /// - Parameters:
    ///   - role: Whether this side is the connecting client or the listening server.
    ///   - passcode: The digits shown on the destination Mac and entered on the source Mac.
    ///   - channelBinding: The TLS 1.3 exporter secret for the current connection.
    ///   - context: A build-unique identity string so builds from different releases can't pair.
    ///   - ephemeralPrivateKey: Injectable for deterministic unit tests; defaults to a fresh
    ///     random scalar for real use.
    init(role: PairingRole, passcode: String, channelBinding: Data, context: String,
         ephemeralPrivateKey: P256.KeyAgreement.PrivateKey = P256.KeyAgreement.PrivateKey()) throws {
        self.role = role
        self.channelBinding = channelBinding
        self.generatorPoint = try Self.hashToCurve(passcode: passcode, channelBinding: channelBinding, context: context)
        self.ephemeralPrivateKey = ephemeralPrivateKey
    }

    /// Computes this side's share, `X(a·G)`, to send to the peer. Must be called before
    /// `deriveKeys`.
    mutating func makeShare() throws -> Data {
        let secret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: generatorPoint)
        let share = secret.withUnsafeBytes { Data($0) }
        myShare = share
        return share
    }

    /// Combines the peer's share with this side's ephemeral scalar to derive the shared
    /// interim session key. Throws `invalidPeerShare` if the peer sent something that isn't a
    /// valid P-256 x-coordinate (this doubles as input validation against malformed messages).
    mutating func deriveKeys(peerShare: Data) throws {
        guard peerShare.count == 32,
              let peerPoint = try? P256.KeyAgreement.PublicKey(compressedRepresentation: Data([0x02]) + peerShare) else {
            throw PairingError.invalidPeerShare
        }
        self.peerShare = peerShare
        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: peerPoint)
        interimSymmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: channelBinding,
            sharedInfo: Data("DataShift-CPace-ISK".utf8) + transcript(),
            outputByteCount: 32
        )
    }

    /// This side's confirmation MAC, to send to the peer once `deriveKeys` has run.
    func confirmation() throws -> Data {
        guard let key = interimSymmetricKey else { throw PairingError.protocolViolation }
        let label = role == .server ? "server" : "client"
        let mac = HMAC<SHA256>.authenticationCode(for: Data(label.utf8) + transcript(), using: key)
        return Data(mac)
    }

    /// Verifies the peer's confirmation MAC. Throws `confirmationMismatch` on a wrong passcode
    /// (or a channel-binding mismatch from a relay attempt).
    func verify(peerConfirmation: Data) throws {
        guard let key = interimSymmetricKey else { throw PairingError.protocolViolation }
        let peerLabel = role == .server ? "client" : "server"
        let expected = HMAC<SHA256>.authenticationCode(for: Data(peerLabel.utf8) + transcript(), using: key)
        guard Data(expected) == peerConfirmation else {
            throw PairingError.confirmationMismatch
        }
    }

    /// The session key derived once both shares are known. `nil` until `deriveKeys` succeeds.
    var sessionKey: SymmetricKey? { interimSymmetricKey }

    /// The exchange transcript (client share, then server share) both sides compute once both
    /// shares are known. Binds the confirmation MACs to this specific exchange.
    private func transcript() -> Data {
        switch role {
        case .client: return (myShare ?? Data()) + (peerShare ?? Data())
        case .server: return (peerShare ?? Data()) + (myShare ?? Data())
        }
    }

    /// Deterministically derives a P-256 base point from the passcode, channel binding, and
    /// build context via try-and-increment: hash a fixed set of inputs plus a counter, and use
    /// the digest as a candidate x-coordinate (with the compressed-point "even y" prefix). Around
    /// half of all 256-bit strings are valid P-256 x-coordinates, so this returns after ~2
    /// attempts on average and fails only with probability roughly 2⁻³² (after all 32 attempts
    /// miss). The number of attempts needed depends only on numeric properties of
    /// `SHA256(label ‖ passcode ‖ channelBinding ‖ context ‖ ctr)`, which are uniformly
    /// distributed for any passcode value — so while this isn't constant-time, the attempt count
    /// doesn't correlate with whether a guessed passcode is right or wrong.
    private static func hashToCurve(passcode: String, channelBinding: Data, context: String) throws -> P256.KeyAgreement.PublicKey {
        let label = Data("DataShift-CPace-G".utf8)
        let passwordData = Data(passcode.utf8)
        let contextData = Data(context.utf8)

        for counter: UInt8 in 0..<32 {
            let input = label + passwordData + channelBinding + contextData + Data([counter])
            let digest = Data(SHA256.hash(data: input))
            if let point = try? P256.KeyAgreement.PublicKey(compressedRepresentation: Data([0x02]) + digest) {
                return point
            }
        }
        throw PairingError.hashToCurveFailed
    }
}
