//
//  PairingMessage.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 25/09/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// Payload carried by the `pairingRequest`/`pairingDecision`/`authHello`/`authResponse`/
/// `authConfirm`/`authResult` message types exchanged during the pairing handshake (see
/// `PairingAuthenticator`). One shared struct is reused across all six message types; which
/// fields are populated depends on which message type carries it:
/// - `pairingRequest`: `hostname` (client's hostname, sent before either side touches the passcode)
/// - `pairingDecision`: `accepted` (the destination human's accept/decline of the pairing request)
/// - `authHello`: `share` (client's PAKE share)
/// - `authResponse`: `share` (server's PAKE share) and `confirmation` (server's MAC)
/// - `authConfirm`: `confirmation` (client's MAC)
/// - `authResult`: `accepted`
struct PairingMessage: Codable {
    /// Lets either side reject a peer running an incompatible future version of this handshake
    /// instead of failing on an unrecognized field.
    let protocolVersion: Int
    var hostname: String?
    var share: Data?
    var confirmation: Data?
    var accepted: Bool?

    static let currentProtocolVersion = 1
}
