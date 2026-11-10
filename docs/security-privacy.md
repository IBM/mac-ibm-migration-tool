---
layout: default
title: Security & privacy
permalink: /security/
---

IBM Data Shift protects data during a device migration with an encrypted, authenticated, direct connection between the two Macs and with strict validation of everything the destination Mac receives. This page is for administrators and security teams running reviews or compliance assessments.

Changes are tagged with the version that introduced them (e.g. {% include tag.html v="2.0.0" %}).

## Security layers

```
┌─────────────────────────────────────────────────────────┐
│  Application Layer                                      │
│  Pairing (accept/decline, PAKE), message validation,    │
│  path and attribute validation on the destination       │
├─────────────────────────────────────────────────────────┤
│  TLS Encryption Layer                                   │
│  next: TLS 1.3, ephemeral certificate, forward secrecy  │
│  v1.4.1: TLS 1.2+, TLS_PSK_WITH_AES_256_GCM_SHA384      │
├─────────────────────────────────────────────────────────┤
│  TCP Transport Layer                                    │
│  Keepalive, No Delay, connection monitoring             │
├─────────────────────────────────────────────────────────┤
│  Network Discovery Layer                                │
│  Bonjour/mDNS with peer-to-peer                         │
└─────────────────────────────────────────────────────────┘
```

## Transport security and pairing {% include tag.html v="2.0.0" %}

Network.framework dropped external pre-shared-key support in TLS 1.3, so the pairing code can no longer gate the TLS handshake. The new version therefore splits the job in two:

1. **Confidential transport (TLS 1.3 only).** The destination Mac serves an ephemeral, self-signed certificate that exists only in memory and is never written to the keychain. It is used purely to obtain an encrypted, **forward-secret** channel. The source Mac accepts any certificate at this layer, because peers are authenticated in the next step.
2. **Peer authentication (application layer).** Immediately after the handshake, both Macs run a CPace-style password-authenticated key exchange (PAKE) that uses the 6-digit pairing code and is **bound to the TLS session's exporter secret**.

### How the pairing handshake works

1. The source sends a `pairingRequest` containing its hostname. Neither side has touched the passcode yet.
2. The destination user explicitly **accepts or declines** the request (`pairingDecision`). The verification code is only usable after acceptance, so a device that merely discovers the service on the network doesn't get to try codes.
3. Both sides derive a P-256 base point from the passcode, the TLS exporter secret and a build-unique context string (hash-to-curve by try-and-increment). The base point is never sent on the network.
4. They exchange ephemeral shares (`authHello`, `authResponse`) and derive a session key with HKDF-SHA256.
5. Both sides exchange confirmation MACs (HMAC-SHA256 over a transcript of both shares, with a different label per role) and verify them (`authConfirm`, `authResult`). A wrong code or a channel-binding mismatch fails verification.

Properties:

- **Relay/man-in-the-middle resistance.** An attacker terminating TLS separately with each side sees different exporter secrets on each leg, so pairing messages can't be relayed, even if the attacker holds valid certificates for both legs.
- **Offline guessing resistance.** The passcode is never sent and a captured exchange doesn't allow testing guesses offline; each guess needs a live handshake.
- **Brute-force lockout.** After 5 wrong-code attempts the destination stops listening and pairing is locked until the user generates a new code.
- **Build isolation.** The build-unique identity is part of the PAKE context, so builds from different releases can't pair.
- **Input validation.** Peer shares that are not valid P-256 x-coordinates are rejected, and the handshake carries a protocol version so incompatible peers are refused cleanly.
- **Passcode.** The code is 6 random digits generated on the destination device and shown on screen. The source user types it in; it is never transmitted.

## Until v1.4.1: TLS-PSK transport

Versions up to v1.4.1 enforce **TLS 1.2 or higher** with the single cipher suite **TLS_PSK_WITH_AES_256_GCM_SHA384**:

- **AES-256-GCM** for authenticated encryption (AEAD).
- **SHA-384** for key derivation and authentication.
- The passcode is turned into a `SymmetricKey`; an HMAC-SHA384 of a *PSK identity* string with that key is registered as the pre-shared key (`sec_protocol_options_add_pre_shared_key`).
- The PSK identity is a random UUID generated at build time by GYB (`BuildIdentity.generated.swift.gyb`), so different builds can't talk to each other even with the same passcode. Debug builds use a fixed identity.
- The negotiated TLS version and cipher suite are logged at connection time.

Limitations of that design, which v2.0.0 removes:

- No forward secrecy (plain PSK key exchange).
- The key was derived from a 6-digit code, so a captured handshake could be attacked offline.
- Any device that discovered the service was shown the pairing code flow without an explicit accept step on the destination.

## Network discovery and isolation

- Bonjour (mDNS) service type `_migrator._tcp` (or the custom identifier from the `networkServiceIdentifier` [setting]({{ '/custom-settings/' | relative_url }})).
- Local network only, peer-to-peer enabled for direct device-to-device links (Wi-Fi or Thunderbolt).
- Proxies are not used (`preferNoProxies`).
- The listener only completes pairing with a valid passcode, and no internet or external server is needed.

## Custom protocol framing

An application protocol runs on top of TLS. Every message starts with a fixed-size header made of three `UInt32` fields: message type, payload length and info length.

- **Type validation**: only known message types are processed (hostname, file, multipart file, available space, result, symlink, directory, metadata, defaults, device info, and, since v2.0.0 version, preferences and the pairing messages {% include tag.html v="2.0.0" %}).
- **Structured parsing**: the header drives how the stream is read, and metadata is separated from file content.
- **Fixed header size**: header parsing reads a fixed number of bytes.

## Destination-side validation {% include tag.html v="2.0.0" %}

Everything coming from the source is treated as untrusted by the destination Mac:

- **Paths and symlinks**: unknown sources, absolute paths and paths containing `..` are refused. Anything that resolves, through existing or dangling symlinks, outside the user's home folder and `/Applications` is refused.
- **Attributes**: only permission bits (without setuid, setgid or sticky) and dates are applied. Ownership and file flags sent by the peer are ignored.
- **Special files**: named pipes, sockets and device files are skipped and logged. Dataless placeholders (for example iCloud items removed by Optimize Mac Storage) are not read, so they are not downloaded on the source.
- **Jamf Self Service**: launched with `/usr/bin/open` using an argument vector instead of an AppleScript shell command, so no value is ever parsed by a shell.
- **`storePath`**: the `storePath` setting (and Jamf's `self_service_app_path`) is only honored if it is an absolute path to an existing `.app` bundle without control characters. Managed Jamf values must be forced by a configuration profile.
- **Preferences**: values are written through `CFPreferences`, and existing destination values are backed up before being overwritten.

## Connection management

### TCP configuration

- **Keepalive** with 1-second idle time and interval and 2 probes, to detect failed connections quickly.
- **No Delay** (Nagle's algorithm disabled) to reduce latency.
- Peer-to-peer enabled and proxies disabled on the connection parameters.

### Monitoring and recovery

- Real-time connection state monitoring.
- Message send retries: up to 5 retries, 2 seconds base delay, doubling on every attempt.
- After the transfer, items that were not migrated are retried up to 3 times before being reported as failed.
- {% include tag.html v="2.0.0" %} A connection-health watchdog detects when no data has moved for 2 minutes, or when a message exhausted all its send retries, and tries to repair the connection instead of stalling.
- {% include tag.html v="2.0.0" %} The source can **pause** a migration. The destination keeps its state and accepts the source's reconnection on resume. A resume that can't reach the destination within 60 seconds returns to the paused screen so it can be retried.

## Threat model

| Threat | Mitigation |
|--------|-----------|
| **Eavesdropping** | TLS encryption (TLS 1.3 in the next release; TLS 1.2 PSK with AES-256-GCM until v1.4.1) |
| **Man-in-the-middle / relay** | Next: PAKE bound to the TLS exporter secret. Until v1.4.1: PSK authentication |
| **Passcode guessing** | Next: no offline attack on a captured handshake, lockout after 5 wrong codes. Until v1.4.1: PSK derived from the code |
| **Unauthorized pairing** | Next: explicit accept/decline on the destination. Until v1.4.1: passcode only |
| **Replay attacks** | Fresh ephemeral values on every handshake, TLS session keys |
| **Data tampering** | Authenticated encryption (AEAD) |
| **Network scanning** | The service can be discovered, but pairing needs the passcode |
| **Malicious source (path traversal, symlink escape)** | Next: destination validates every path and symlink and ignores peer ownership and flags |
| **Command injection through settings** | Next: no shell is used to launch Self Service, `storePath` is validated |
| **Stalled connections** | TCP keepalive, retries, and next: connection-health watchdog |
| **Malformed messages** | Fixed-size header parsing and message type validation |

## Known limitations

- The protocol header carries a `UInt32` payload length and no explicit maximum payload size is enforced by the framing layer.
- Pairing still depends on a 6-digit code; the lockout and the live-handshake requirement are what make guessing impractical, so keep the Macs on trusted networks.
- Until v1.4.1 there was no operation timeout in the app; failures were detected through TCP keepalive and the connection state. The next release adds the watchdog described above.

## Privacy

- **No cloud services**: all data goes directly between the two devices.
- **No external servers**: nothing is sent outside the local connection.
- **Local processing**: all file analysis happens locally.
- **No telemetry**: the app does not collect or transmit usage data.
- **User control**: users decide what gets migrated.

## Required permissions

Grant these through a [PPPC profile]({{ '/pppc-deployment/' | relative_url }}):

- Full Disk Access (`SystemPolicyAllFiles`)
- Desktop folder access (`SystemPolicyDesktopFolder`)
- Documents folder access (`SystemPolicyDocumentsFolder`)
- Downloads folder access (`SystemPolicyDownloadsFolder`)

NB: Local Network access, used for device discovery, must still be granted by the user, as it cannot be forced through MDM. IBM Data Shift can detect if this permission is missing and notify the user.

## Security audit log

Security-relevant events go through the app's logging system and can be read in Console.app. {% include tag.html v="2.0.0" %} Logs are now categorized (Migration, Network, Pairing, Discovery, Report, Device) so they are easier to filter. Use the `loggingLevel` [setting]({{ '/custom-settings/' | relative_url }}) (`noLog`, `standard`, `debug`) to control the verbosity.

Events logged include connection establishment and termination, TLS negotiation details, pairing attempts and failures, protocol errors, file transfer operations and retry events.

## Best practices

**For users**
1. Perform migrations on trusted, private networks.
2. Keep the devices physically close.
3. Confirm the hostname of the requesting device before accepting a pairing request {% include tag.html v="2.0.0" %}.
4. Don't share the passcode shown on the new device.
5. Watch for unexpected connection failures or errors.

**For administrators**
1. Allow Bonjour/mDNS traffic on the local networks used for migrations.
2. Deploy PPPC and custom-settings profiles through MDM.
3. Enable detailed logging only when you need it for audits or troubleshooting.
4. Keep IBM Data Shift updated to receive security fixes.
5. Consider network segmentation for sensitive migrations.

## Standards

- NIST SP 800-52 Rev. 2: guidelines for TLS implementations.
- NIST SP 800-107 Rev. 1: recommendation for applications using approved hash algorithms.
- RFC 8446: TLS 1.3 (next release) and RFC 5246: TLS 1.2 (until v1.4.1).
- RFC 4279 and RFC 5487: pre-shared key cipher suites for TLS (until v1.4.1).
- Apple Platform Security guidance for macOS apps.

## Reporting a security issue

If you find a vulnerability:

1. **Do not** disclose it publicly.
2. Contact the project maintainers, see [MAINTAINERS.md]({{ site.repo_url }}/blob/main/MAINTAINERS.md).
3. Provide as much detail as possible.
4. Allow reasonable time for a fix.

More resources: [SECURITY.md]({{ site.repo_url }}/blob/main/SECURITY.md) in the repository.
