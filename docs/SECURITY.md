# IBM Data Shift Security Architecture

## Overview

IBM Data Shift implements a multi-layered security approach to ensure secure communication between source and destination devices during the migration process. This document details the security measures, protocols, and cryptographic implementations used to protect data in transit.

## Table of Contents

1. [Security Architecture Overview](#security-architecture-overview)
2. [Transport Layer Security (TLS)](#transport-layer-security-tls)
3. [Pre-Shared Key (PSK) Authentication](#pre-shared-key-psk-authentication)
4. [Network Discovery and Isolation](#network-discovery-and-isolation)
5. [Custom Protocol Framing](#custom-protocol-framing)
6. [Connection Management](#connection-management)
7. [Security Best Practices](#security-best-practices)

---

## Security Architecture Overview

IBM Data Shift employs a defense-in-depth strategy with the following security layers:

```
┌─────────────────────────────────────────────────────────┐
│              Application Layer                          │
│  (Custom Protocol Framing & Message Validation)         │
├─────────────────────────────────────────────────────────┤
│              TLS 1.2+ Encryption Layer                  │
│  (AES-256-GCM with PSK Authentication)                  │
├─────────────────────────────────────────────────────────┤
│              TCP Transport Layer                        │
│  (Keepalive, No Delay, Connection Monitoring)           │
├─────────────────────────────────────────────────────────┤
│              Network Discovery Layer                    │
│  (Bonjour/mDNS with Peer-to-Peer)                       │
└─────────────────────────────────────────────────────────┘
```

---

## Transport Layer Security (TLS)

### TLS Configuration

IBM Data Shift enforces **TLS 1.2 or higher** for all network communications between devices.

**Implementation:** [`NWParameters-Extension.swift:73`](../migrator/Extensions/NWParameters-Extension.swift:73)

```swift
sec_protocol_options_set_min_tls_protocol_version(
    tlsOptions.securityProtocolOptions, 
    .TLSv12
)
```

### Cipher Suite

The application uses the **TLS_PSK_WITH_AES_256_GCM_SHA384** cipher suite, which provides:

- **AES-256-GCM**: Advanced Encryption Standard with 256-bit keys in Galois/Counter Mode
  - Provides both confidentiality and authenticity
  - Authenticated encryption with associated data (AEAD)
  - Resistant to padding oracle attacks

- **SHA-384**: Secure Hash Algorithm with 384-bit output
  - Used for HMAC authentication
  - Provides strong collision resistance

**Implementation:** [`NWParameters-Extension.swift:69-70`](../migrator/Extensions/NWParameters-Extension.swift:69-70)

```swift
sec_protocol_options_append_tls_ciphersuite(
    tlsOptions.securityProtocolOptions,
    tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_256_GCM_SHA384))!
)
```

### TLS Verification

Upon successful connection establishment, the application logs the negotiated TLS version and cipher suite for verification:

**Implementation:** [`NetworkConnection.swift:104-108`](../migrator/Controllers/NetworkControllers/NetworkConnection.swift:104-108)

```swift
if let metadata = self.connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata {
    let version = sec_protocol_metadata_get_negotiated_tls_protocol_version(metadata.securityProtocolMetadata)
    let suite = sec_protocol_metadata_get_negotiated_tls_ciphersuite(metadata.securityProtocolMetadata)
    MLogger.main.log("Negotiated TLS version: \(version), suite: \(suite)", type: .debug)
}
```

---

## Pre-Shared Key (PSK) Authentication

### Overview

IBM Data Shift uses **Pre-Shared Key (PSK) authentication** to ensure that only authorized devices can establish connections. This eliminates the need for certificate management while providing strong mutual authentication.

### Passcode Generation and Exchange

1. **User-Generated Passcode**: A unique passcode is generated on the source device
2. **Out-of-Band Verification**: The user manually enters this passcode on the destination device
3. **No Network Transmission**: The passcode itself is never transmitted over the network

**Implementation:** [`NetworkServer.swift:39-40`](../migrator/Controllers/NetworkControllers/NetworkServer.swift:39-40)

### Key Derivation Process

The PSK is derived using the following cryptographic process:

1. **Passcode to Data Conversion**: The user-provided passcode is converted to UTF-8 data
2. **Symmetric Key Creation**: A `SymmetricKey` is created from the passcode data
3. **Identity String**: A unique identity string is used (build-specific in production)
4. **HMAC-SHA384 Authentication**: An authentication code is generated using HMAC with SHA-384

**Implementation:** [`NWParameters-Extension.swift:43-54`](../migrator/Extensions/NWParameters-Extension.swift:43-54)

```swift
guard let passcodeData = passcode.data(using: .utf8) else { return tlsOptions }
let authenticationKey = SymmetricKey(data: passcodeData)

#if DEBUG
let pskIdentity = "MigrationController-Debug"
#else
let pskIdentity = TLSPSKIdentity.value
#endif

let authenticationCode = HMAC<SHA384>.authenticationCode(
    for: Data(pskIdentity.utf8), 
    using: authenticationKey
)
```
### Build-Time PSK Identity Generation

To enhance security, IBM Data Shift generates a **unique PSK identity for each build** using the GYB (Generate Your Boilerplate) templating system. This ensures that different builds cannot intercommunicate, even if they share the same passcode.

**GYB Template:** [`BuildIdentity.generated.swift.gyb`](../migrator/Generated/BuildIdentity.generated.swift.gyb)

```python
%{
import uuid
import datetime
# Generate a fresh random UUID for each render
random_uuid = str(uuid.uuid4())
generated_at = datetime.datetime.utcnow().isoformat() + 'Z'
}%

public enum TLSPSKIdentity {
    public static let value: String = "${random_uuid}"
}
```

**Build Process:**

1. **Pre-Build Phase**: The GYB script executes during the Xcode build process
2. **UUID Generation**: A cryptographically random UUID v4 is generated using Python's `uuid.uuid4()`
3. **Code Generation**: The UUID is embedded into Swift code as `TLSPSKIdentity.value`
4. **Compilation**: The generated Swift file is compiled into the application binary

**Security Benefits:**

- **Build Isolation**: Each build has a unique identity, preventing cross-build communication
- **Deployment Control**: Organizations can ensure only authorized builds can communicate
- **Replay Prevention**: Captured network traffic from one build cannot be replayed against another
- **Distribution Security**: Different distribution channels can have distinct identities
- **Forensic Tracking**: Build-specific identities aid in security incident investigation

**Example Generated Output:**

```swift
public enum TLSPSKIdentity {
    public static let value: String = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

**Note:** In DEBUG builds, a static identity string (`"MigrationController-Debug"`) is used to facilitate development and testing. Production builds always use the GYB-generated UUID.


### PSK Integration with TLS

The derived authentication code and identity are added to the TLS security protocol options:

**Implementation:** [`NWParameters-Extension.swift:65-67`](../migrator/Extensions/NWParameters-Extension.swift:65-67)

```swift
sec_protocol_options_add_pre_shared_key(
    tlsOptions.securityProtocolOptions,
    authenticationDispatchData as __DispatchData,
    identityDispatchData as __DispatchData
)
```

### Security Properties

- **Mutual Authentication**: Both devices must possess the same passcode
- **Forward Secrecy**: Each session uses ephemeral keys derived from the PSK
- **Replay Protection**: TLS nonces prevent replay attacks
- **Man-in-the-Middle Protection**: Without the correct passcode, attackers cannot decrypt or inject traffic

---

## Network Discovery and Isolation

### Bonjour/mDNS Service Discovery

IBM Data Shift uses **Bonjour (mDNS)** for local network device discovery with the following security considerations:

**Service Type:** `_migrator._tcp` (or custom identifier from `AppContext.networkServiceIdentifier`)

**Implementation:** [`NetworkServer.swift:42`](../migrator/Controllers/NetworkControllers/NetworkServer.swift:42)

```swift
listener?.service = NWListener.Service(type: AppContext.networkServiceIdentifier+"._tcp")
```

### Peer-to-Peer Mode

The application enables **peer-to-peer networking**, allowing direct device-to-device communication without requiring infrastructure:

**Implementation:** [`NWParameters-Extension.swift:27`](../migrator/Extensions/NWParameters-Extension.swift:27)

```swift
self.includePeerToPeer = true
```

### Network Isolation Features

1. **No Proxy Usage**: Direct connections only, preventing proxy-based attacks
   
   **Implementation:** [`NWParameters-Extension.swift:29`](../migrator/Extensions/NWParameters-Extension.swift:29)
   ```swift
   self.preferNoProxies = true
   ```

2. **Local Network Only**: Discovery is limited to the local network segment
3. **Passcode-Protected Listener**: The server only accepts connections with valid passcodes

   **Implementation:** [`NetworkServer.swift:39-40`](../migrator/Controllers/NetworkControllers/NetworkServer.swift:39-40)
   ```swift
   func start(withPasscode passcode: String) throws {
       let parameters = NWParameters(passcode: passcode)
   ```

---

## Custom Protocol Framing

### Protocol Overview

IBM Data Shift implements a custom application-layer protocol ([`MigratorNetworkProtocol`](../migrator/Model/Network/MigratorNetworkProtocol.swift)) on top of TLS to provide:

- Message type identification
- Payload length validation
- Metadata transmission
- Structured data transfer

### Protocol Header Structure

Each message includes a header with three `UInt32` fields (12 bytes total):

**Implementation:** [`MigratorNetworkProtocolHeader.swift:18-20`](../migrator/Model/Network/MigratorNetworkProtocolHeader.swift:18-20)

```swift
static var encodedSize: Int {
    return (MemoryLayout<UInt32>.size * 3)  // 12 bytes
}
```

**Header Fields:**
1. **Type** (4 bytes): Message type identifier
2. **Length** (4 bytes): Payload length in bytes
3. **Info Length** (4 bytes): Metadata length in bytes

### Message Type Validation

The protocol validates message types to prevent malformed or malicious messages:

**Implementation:** [`MigratorNetworkProtocol.swift:99-103`](../migrator/Model/Network/MigratorNetworkProtocol.swift:99-103)

```swift
var messageType = MigratorMessageType.invalid
if let parsedMessageType = MigratorMessageType(rawValue: header.type) {
    messageType = parsedMessageType
}
```

### Security Benefits

- **Length Validation**: Prevents buffer overflow attacks
- **Type Safety**: Ensures only valid message types are processed
- **Structured Parsing**: Reduces attack surface by enforcing message format
- **Metadata Separation**: Allows secure transmission of file attributes and metadata

---

## Connection Management

### TCP Configuration

IBM Data Shift configures TCP with security-focused settings:

**Implementation:** [`NWParameters-Extension.swift:18-23`](../migrator/Extensions/NWParameters-Extension.swift:18-23)

```swift
let tcpOptions = NWProtocolTCP.Options()
tcpOptions.enableKeepalive = true
tcpOptions.keepaliveIdle = 1
tcpOptions.keepaliveCount = 2
tcpOptions.keepaliveInterval = 1
tcpOptions.noDelay = true
```

**Security Benefits:**
- **Keepalive**: Detects connection failures and prevents stale connections
- **No Delay**: Reduces latency and prevents timing-based attacks
- **Fast Detection**: Quick identification of connection issues (1-second intervals)

### Connection State Monitoring

The application continuously monitors connection states and handles failures gracefully:

**Implementation:** [`NetworkConnection.swift:100-114`](../migrator/Controllers/NetworkControllers/NetworkConnection.swift:100-114)

```swift
connection.stateUpdateHandler = { newState in
    self.logger.log("networkConnection.stateUpdateHandler: newState \"\(String(describing: newState))\"", type: .default)
    self.onNewConnectionState.send(newState)
    if case .ready = newState {
        // Verify TLS negotiation
        // Start receiving messages
    }
}
```

### Timeout Protection

Operations include timeout mechanisms to prevent indefinite hangs:

**Implementation:** [`NetworkConnection.swift:217-221`](../migrator/Controllers/NetworkControllers/NetworkConnection.swift:217-221)

```swift
let timeoutTask = Task {
    try await Task.sleep(nanoseconds: 120_000_000_000)  // 120 seconds
    continuation.resume(throwing: NSError(domain: "NetworkConnection", code: 1002,
                                       userInfo: [NSLocalizedDescriptionKey: "Send operation timed out"]))
}
```

### Retry Logic with Exponential Backoff

Failed operations are retried with delays to prevent resource exhaustion:

**Implementation:** [`NetworkConnection.swift:209-243`](../migrator/Controllers/NetworkControllers/NetworkConnection.swift:209-243)

```swift
private func sendAsyncWrapper(content: Data,
                              contentContext: NWConnection.ContentContext = .defaultMessage,
                              maxRetries: Int = 3,
                              retryDelay: TimeInterval = 2) async throws
```

---

## Security Best Practices

### For Users

1. **Trusted Networks**: Perform migrations on trusted, private networks
2. **Physical Proximity**: Keep devices in close physical proximity during migration
3. **Verify Devices**: Confirm device hostnames before proceeding
4. **Monitor Progress**: Watch for unexpected connection failures or errors

### For Administrators

1. **Firewall Rules**: Ensure Bonjour/mDNS traffic is allowed on local networks
2. **Logging**: Enable detailed logging for security audits
3. **Update Policy**: Keep IBM Data Shift updated to receive security patches

### For Developers

1. **Code Review**: All network-related code undergoes security review
2. **Dependency Management**: Regular updates of cryptographic libraries
3. **Static Analysis**: Use SwiftLint and security scanning tools
4. **Penetration Testing**: Regular security assessments of the protocol
5. **Incident Response**: Documented procedures for security vulnerabilities

---

## Threat Model and Mitigations

| Threat | Mitigation |
|--------|-----------|
| **Eavesdropping** | TLS 1.2+ with AES-256-GCM encryption |
| **Man-in-the-Middle** | PSK authentication with HMAC-SHA384 |
| **Replay Attacks** | TLS nonces and session keys |
| **Unauthorized Access** | Passcode-protected connections |
| **Network Scanning** | Bonjour service requires passcode to connect |
| **Data Tampering** | Authenticated encryption (GCM mode) |
| **Connection Hijacking** | TCP keepalive and state monitoring |
| **Denial of Service** | Timeout mechanisms and retry limits |
| **Buffer Overflow** | Length validation in protocol headers |
| **Protocol Confusion** | Strict message type validation |

---

## Compliance and Standards

IBM Data Shift's security implementation aligns with:

- **NIST SP 800-52 Rev. 2**: Guidelines for TLS implementations
- **NIST SP 800-107 Rev. 1**: Recommendation for applications using approved hash algorithms
- **RFC 8446**: The Transport Layer Security (TLS) Protocol Version 1.3
- **RFC 4279**: Pre-Shared Key Ciphersuites for TLS
- **Apple Platform Security**: Follows Apple's security best practices for macOS applications

---

## Security Audit Log

All security-relevant events are logged through the [`MLogger`](../migrator/Controllers/MLogger.swift) system:

- Connection establishment and termination
- TLS negotiation details
- Authentication attempts
- Protocol errors and violations
- File transfer operations
- Timeout and retry events

---

## Reporting Security Issues

If you discover a security vulnerability in IBM Data Shift, please report it responsibly:

1. **Do not** disclose the vulnerability publicly
2. Contact the maintainers through the project's security contact
3. Provide detailed information about the vulnerability
4. Allow reasonable time for a fix to be developed and deployed

---

## Conclusion

IBM Data Shift implements enterprise-grade security measures to protect data during device migrations. The combination of TLS 1.2+, PSK authentication, custom protocol framing, and robust connection management provides multiple layers of defense against common network attacks.

The security architecture ensures:
- **Confidentiality**: All data is encrypted in transit
- **Integrity**: Data cannot be tampered with undetected
- **Authentication**: Only authorized devices can connect
- **Availability**: Robust error handling and retry mechanisms

For questions or concerns about IBM Data Shift's security implementation, please contact project's maintainers [MAINTAINERS.md](../MAINTAINERS.md).

---

*Last Updated: 2025-11-06*  
*Document Version: 1.0*