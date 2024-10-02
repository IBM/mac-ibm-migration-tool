//
//  NWParameters-Extension.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 11/01/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import Network
import CryptoKit

extension NWParameters {
    /// Initializes `NWParameters` with TCP and custom TLS settings, including a pre-shared key for TLS authentication.
    /// - Parameter passcode: A `String` used to derive the pre-shared key for TLS authentication.
    convenience init(passcode: String) {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 1
        tcpOptions.keepaliveCount = 2
        tcpOptions.keepaliveInterval = 1

        // Initialize `NWParameters` with custom TLS options (derived from the passcode) and the specified TCP options.
        self.init(tls: NWParameters.tlsOptions(passcode: passcode), tcp: tcpOptions)
        self.includePeerToPeer = true
        self.attribution = .developer
        self.preferNoProxies = true
        
        // Configure custom application protocol using `MigratorNetworkProtocol`.
        let migratorOptions = NWProtocolFramer.Options(definition: MigratorNetworkProtocol.definition)
        self.defaultProtocolStack.applicationProtocols.insert(migratorOptions, at: 0)
    }

    /// Generates TLS options including a pre-shared key derived from a passcode.
    /// - Parameter passcode: The passcode used to derive the pre-shared key.
    /// - Returns: A configured `NWProtocolTLS.Options` instance.
    private static func tlsOptions(passcode: String) -> NWProtocolTLS.Options {
        let tlsOptions = NWProtocolTLS.Options()

        // Derive a symmetric key from the passcode.
        let authenticationKey = SymmetricKey(data: passcode.data(using: .utf8)!)
        // Create an authentication code for "MigratorNetworkProtocol" using HMAC with SHA256.
        let authenticationCode = HMAC<SHA256>.authenticationCode(for: "MigratorNetworkProtocol".data(using: .utf8)!, using: authenticationKey)

        // Convert the authentication code to `DispatchData`.
        let authenticationDispatchData = authenticationCode.withUnsafeBytes {
            DispatchData(bytes: $0)
        }
        // Add the pre-shared key to the TLS options.
        sec_protocol_options_add_pre_shared_key(tlsOptions.securityProtocolOptions,
                                                authenticationDispatchData as __DispatchData,
                                                stringToDispatchData("MigratorNetworkProtocol")! as __DispatchData)
        // Append the cipher suite `TLS_PSK_WITH_AES_128_GCM_SHA256` to the TLS options.
        sec_protocol_options_append_tls_ciphersuite(tlsOptions.securityProtocolOptions,
                                                    tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        return tlsOptions
    }

    /// Converts a `String` to `DispatchData`.
    /// - Parameter string: The `String` to be converted.
    /// - Returns: The converted `DispatchData`, or `nil` if the conversion fails.
    private static func stringToDispatchData(_ string: String) -> DispatchData? {
        guard let stringData = string.data(using: .utf8) else {
            return nil
        }
        let dispatchData = stringData.withUnsafeBytes {
            DispatchData(bytes: $0)
        }
        return dispatchData
    }
}
