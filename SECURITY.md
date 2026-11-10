# Security Policy

## Supported Versions

| Version   | Supported          |
| --------- | ------------------ |
| 2.0.0     | :white_check_mark: |
| 1.4.x     | :white_check_mark: |
| 1.3.0     | :x:                |
| 1.2.0     | :x:                |
| 1.1.1     | :x:                |
| 1.1.0     | :x:                |
| 1.0.0     | :x:                |

## Device Pairing & Transport Security

IBM Data Shift pairs and transfers data between two Macs over a direct peer-to-peer connection. As of 2.0.0:

- **Transport**: The connection is secured with **TLS 1.3**. Because TLS 1.3 removed Network.framework's external-PSK mode, the destination Mac serves an ephemeral, self-signed certificate generated fresh for each run and held only in memory - its private key is never written to the keychain or disk. This certificate provides encryption and forward secrecy for the transport only; it is **not** used to authenticate either peer's identity.
- **Peer authentication**: The 6-digit verification code shown on the destination Mac and entered on the source Mac is checked at the application layer via a CPace-style password-authenticated key exchange (PAKE), cryptographically bound to the TLS 1.3 channel's exporter secret. This binding means an attacker who terminates separate TLS sessions with each device (a classic relay/man-in-the-middle position) cannot pass the pairing check, even while holding valid certificates on both legs.
- **Pairing consent**: The destination Mac must explicitly accept or decline each incoming pairing request before its verification code becomes usable. The code is never exposed to a device that has not been explicitly approved.
- **Brute-force mitigation**: Repeated incorrect verification code submissions lock pairing on the destination device; a human must generate a fresh code to resume, preventing unattended guessing of the 6-digit code.

## Receive-side Validation

- **Path confinement**: The destination only writes inside the user's home folder and `/Applications`. Paths with an unknown source, absolute paths, or `..` components are rejected, and paths are resolved through existing (including dangling) symlinks before being checked.
- **Symlink targets**: Symbolic links received from the source are created only if their target resolves inside those same locations.
- **Attribute sanitization**: Only permission bits (no setuid/setgid/sticky) and dates are applied from the peer's file attributes.
- **No shell execution**: Jamf Self Service is launched through `/usr/bin/open` with an argument vector, and the configured `storePath` must be an existing `.app` bundle path.

If you identify a weakness in this pairing or transport design, please report it following the process below rather than disclosing it publicly.

## Reporting a Vulnerability

To report a vulnerability, please e-mail to [maintainers](/MAINTAINERS.md) of this project with a description of the issue,
the steps you took to create the issue, affected versions, and if known, mitigations for the issue.

We should reply within three working days, probably much sooner.

We use GitHub's security advisory feature to track open security issues. You should expect
a close collaboration as we work to resolve the issue you have reported.

You may also reach out to the team via [Github Discussions](https://github.com/IBM/mac-ibm-migration-tool/discussions)
