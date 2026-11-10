//
//  NWParameters-Extension.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 11/01/2024.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Network
import Foundation

extension NWParameters {
    /// Initializes `NWParameters` for TLS 1.3.
    ///
    /// TLS 1.3 dropped Network.framework's external-PSK mode, so the pairing code can no longer
    /// gate the TLS handshake itself. Instead:
    /// - The server passes its `tlsIdentity` (see `EphemeralTLSIdentity`), a throwaway self-signed
    ///   certificate used only for confidentiality and forward secrecy.
    /// - The client passes `nil` and deliberately accepts any certificate the server presents,
    ///   because peer authentication happens afterwards at the application layer via
    ///   `PairingAuthenticator`, bound to this TLS session's exporter secret.
    /// - Parameter tlsIdentity: The local TLS identity to present, or `nil` for a client that
    ///   doesn't authenticate the server at the TLS layer.
    convenience init(tlsIdentity: sec_identity_t?) {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 1
        tcpOptions.keepaliveCount = 2
        tcpOptions.keepaliveInterval = 1
        tcpOptions.noDelay = true

        // Initialize `NWParameters` with TLS 1.3 options and the specified TCP options.
        self.init(tls: NWParameters.tlsOptions(identity: tlsIdentity), tcp: tcpOptions)
        self.includePeerToPeer = true
        self.attribution = .developer
        self.preferNoProxies = true

        // Configure custom application protocol using `MigratorNetworkProtocol`.
        let migratorOptions = NWProtocolFramer.Options(definition: MigratorNetworkProtocol.definition)
        self.defaultProtocolStack.applicationProtocols.insert(migratorOptions, at: 0)
    }

    /// Builds TLS 1.3-only options, presenting `identity` (if any) as the local identity.
    /// - Parameter identity: The local TLS identity to present, or `nil` on the client.
    /// - Returns: A configured `NWProtocolTLS.Options` instance.
    private static func tlsOptions(identity: sec_identity_t?) -> NWProtocolTLS.Options {
        let tlsOptions = NWProtocolTLS.Options()
        let securityOptions = tlsOptions.securityProtocolOptions

        sec_protocol_options_set_min_tls_protocol_version(securityOptions, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(securityOptions, .TLSv13)

        if let identity {
            sec_protocol_options_set_local_identity(securityOptions, identity)
        } else {
            // Accept any server certificate: it's an ephemeral, throwaway identity with no
            // meaningful chain of trust. The actual peer authentication happens afterwards via
            // the application-layer PAKE exchange, bound to this exact TLS session.
            sec_protocol_options_set_verify_block(securityOptions, { _, _, complete in
                complete(true)
            }, .main)
        }

        return tlsOptions
    }
}
