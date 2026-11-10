---
layout: default
title: Architecture overview
permalink: /architecture/
---

IBM Data Shift is a native macOS application built with SwiftUI that migrates files, applications and preferences between Mac devices over a direct peer-to-peer connection. This page gives developers and technical administrators an architectural overview.

Security implementation details (cryptography, authentication, protocol hardening, threat model) are in [Security & privacy]({{ '/security/' | relative_url }}). Changes from the unreleased development branch are tagged {% include tag.html v="2.0.0" %}.

## High-level architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         macOS Device                            │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │          IBM Data Shift (SwiftUI Native App)            │    │
│  │  - Runs entirely locally on macOS                       │    │
│  │  - No external servers required                         │    │
│  │  - Peer-to-peer network architecture                    │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
                               ║
                               ║ Encrypted peer-to-peer connection
                               ║ (Bonjour discovery + TLS, passcode-authenticated)
                               ║
┌─────────────────────────────────────────────────────────────────┐
│                    Second macOS Device                          │
│  - Same app running in the opposite role (source/destination)   │
│  - Passcode-authenticated connection                            │
│  - No internet or external servers required                     │
└─────────────────────────────────────────────────────────────────┘
```

## Application layers

### 1. Application layer

- **MigratorApp (SwiftUI)**: app lifecycle, window configuration, menu commands.
- **MainView (SwiftUI)**: page navigation and orchestration of the migration workflow.
- **AppContext**: configuration management, UserDefaults integration, managed (MDM profile) settings.

### 2. Controller layer

- **MigrationController** (singleton): central migration orchestration, state management from discovery to completion, operating mode (server/browser), progress tracking and reporting. The migration verifies completion, and items that failed are retried a limited number of times before being reported. {% include tag.html v="2.0.0" %} It also handles pairing lockout, pause/resume and connection restoration.
- **Network controllers**
  - **NetworkServer**: listener, Bonjour service advertisement, passcode authentication (destination device).
  - **NetworkBrowser**: Bonjour browsing and peer-to-peer discovery (source device).
  - **NetworkConnection**: data transfer, protocol framing and message handling, with send retry logic. {% include tag.html v="2.0.0" %} Also runs the pairing handshake, a connection-health watchdog, and writes received data off the connection queue.
  - **PairingAuthenticator** {% include tag.html v="2.0.0" %}: CPace-style PAKE bound to the TLS exporter secret.
  - **EphemeralTLSIdentity** {% include tag.html v="2.0.0" %}: in-memory, self-signed TLS identity served by the destination.
- **ArchitectureDetector**: checks application compatibility (Intel vs. Apple Silicon).
- **DeviceManagementHelper**: verifies MDM enrollment status.
- **JamfReconManager**: manages Jamf inventory updates.
- **MigrationReportController**: generates migration reports.
- **MLogger**: logging with configurable verbosity. {% include tag.html v="2.0.0" %} Categorized by area (Migration, Network, Pairing, Discovery, Report, Device).
- **PreferencesDiscovery** {% include tag.html v="2.0.0" %}: discovers macOS preferences and groups them for selection.
- **AppPathDiscovery** and **FileSizeCache** {% include tag.html v="2.0.0" %}: discover app support files and cache size calculations.
- **MigrationETAEstimator** and **ETADisplayStabilizer**: estimate the remaining time and keep the displayed value stable.

### 3. Secure transport layer

All transfers between the two devices are encrypted and authenticated with a passcode shown on the destination device, with no external services.

- **Until v1.4.1**: TLS 1.2+ with a pre-shared key derived from the passcode (`TLS_PSK_WITH_AES_256_GCM_SHA384`) and a build-unique PSK identity.
- **Next release** {% include tag.html v="2.0.0" %}: TLS 1.3 with an ephemeral in-memory certificate on the destination for forward-secret encryption, plus an application-layer PAKE (`PairingAuthenticator`) bound to the TLS session and an explicit accept/decline step on the destination.

See [Security & privacy]({{ '/security/' | relative_url }}) for details.

### 4. Model layer

- **Core models**: `MigrationItem`, `MigrationOption` (Lite, Complete, Advanced), `MigratorFile`, `DiscoveredApplication`, `MigratorPage`. {% include tag.html v="2.0.0" %} `MigrationPreset`, `PreferenceCatalog`, `PreferenceGroup`, `AppInfo` and `FileScanner`.
- **Network protocol models**: `MigratorNetworkProtocol`, `MigratorMessageType`, and the messages exchanged between devices (`DeviceInfoMessage`, `FileMessage`, `DefaultsMessage`, `SymbolicLinkMessage`). {% include tag.html v="2.0.0" %} `PairingMessage` and `PreferencesMessage`.
- **Device management models**: `ManagedEnvironment`, `DeviceManagementState`.

### 5. View layer

Migration workflow views, in order ({% include tag.html v="2.0.0" %} the setup flow also gains preference selection, an expandable per-app support file breakdown and a paused screen):

| View | Purpose |
|------|---------|
| WelcomeView | Initial screen with device role selection |
| BrowserView | Discover the new device (on the old device) |
| ServerView | Wait for a connection and show the passcode (on the new device) |
| CodeVerificationView | Passcode entry |
| MigrationSetupView | Select the migration option, architecture and storage checks |
| RecapView | Migration summary (optional) |
| MigrationView | Migration progress |
| AppleIDView | Apple ID login check (optional) |
| RebootView | Reboot countdown (optional) |
| JamfReconView | Inventory update (optional) |
| FinalView | Completion screen |

Common UI components include `CardButton`, `CustomAlertView`, `MigratorFileView`, `DeviceListRow`, `ScrollingTextView` and `CustomizableIconView`.

## Key features

### Peer-to-peer architecture

1. **No central server**: devices talk directly to each other.
2. **Local network**: discovery and transfer happen on the local network.
3. **Bonjour/mDNS**: service discovery through Apple's Bonjour.
4. **Multiple transports**: Wi-Fi and Thunderbolt connections are supported.

### Migration modes

- **Lite**: Desktop and Documents folders only.
- **Complete**: all applications, user preferences and the entire User folder, excluding most of Library (Application Support and Preferences are included).
- **Advanced selection**: manual selection of files and applications. Until v1.4.1, user preferences and Application Support of the selected apps are not migrated. {% include tag.html v="2.0.0" %} Support files are discovered per app, and preference groups can be selected individually.
- **Custom presets** {% include tag.html v="2.0.0" %}: administrators can replace Lite and Complete with their own presets (`migrationPresets` setting).

### Pause and resume {% include tag.html v="2.0.0" %}

The source can pause a running migration after the in-flight data is finished. The destination keeps its state and automatically accepts the source's reconnection, resuming from the same point. A resume that can't reach the destination within 60 seconds returns to the paused screen.

### Discovery and scanning {% include tag.html v="2.0.0" %}

- App support files (Application Support, Containers, Group Containers, preferences) are discovered automatically, and directory listings shared across apps are cached.
- Shared vendor-wide Group Containers are matched one level deeper for an app-specific subfolder instead of migrating the whole container.
- Exclusion rules apply at every depth, and caches, dataless cloud placeholders, named pipes, sockets and device files are skipped.

### Architecture compatibility (v1.4.0+)

Applications are checked for compatibility with the destination architecture (Intel vs. Apple Silicon). Users can ignore, review or migrate incompatible applications anyway. The check can be disabled with the `checkAppsArchitecture` [custom setting]({{ '/custom-settings/' | relative_url }}).

### Storage check

The source device asks the destination for its available space and blocks the migration if the selection would leave less than 10 GB free. Since v1.4.1, if the destination space can't be determined, the user sees a warning instead.

### Configuration management

- **Compile-time**: values in `AppContext.swift`, requiring recompilation. They act as defaults and fallbacks.
- **Runtime**: values deployed through MDM configuration profiles (UserDefaults), updatable without recompiling. See [Custom settings]({{ '/custom-settings/' | relative_url }}).

## macOS system integration

**Frameworks**: Foundation, Network (Bonjour and peer-to-peer connections), AppKit, SwiftUI, Combine, CryptoKit, Security.

**System services**: FileManager, UserDefaults, Bonjour/mDNS, Network.framework, and Launch Agents for restarting the app after a reboot.

**Optional MDM integration**: Jamf Pro inventory updates (recon), configuration profiles for custom settings, managed preferences, and PPPC profiles for privacy permissions.

## Data flow

### Discovery

1. The user launches the app on both devices and selects the role of each.
2. The new device starts the `NetworkServer` (listener).
3. The old device starts the `NetworkBrowser` (discovery).
4. Bonjour advertises and discovers the service.
5. The user selects the target device from the list.

### Connection

1. The user enters the passcode shown on the new device.
2. A secured connection is established between the devices.
3. The devices exchange device information.
4. The connection is verified and ready.

### Migration

1. The user selects the migration mode.
2. The app scans the source device for files and apps.
3. Architecture compatibility and storage checks run.
4. The user reviews and confirms the selection.
5. Files are transferred over the encrypted connection.
6. Progress is tracked on both devices.
7. The app verifies that all selected items were migrated, retrying failed ones.

### Post-migration

1. Apple ID login check (optional).
2. System reboot (Complete migration).
3. Jamf inventory update (optional).
4. Migration report generation (optional).
5. Completion screen.

## Customization points

- **Branding**: app name and bundle identifier, app and page icons, organization name, copyright, font family.
- **Behavior**: MDM environment check, post-migration steps (Apple ID, Jamf recon, reboot), migration summary page, Terms & Conditions acceptance, duplicate file handling policy.
- **Scope** {% include tag.html v="2.0.0" %}: migration presets, preferences and app support file migration, and excluding the Applications folders.
- **Migration scope**: URL exclusion list and explicit allow list (with regex support), excluded file extensions and prefixes.
- **User interface**: custom page icons, welcome page information, legal document links.

See [Custom settings]({{ '/custom-settings/' | relative_url }}) for all options.

## Performance considerations

- **Memory**: since v1.2.0 RAM usage is 90-95% lower than v1.1.x thanks to optimized file discovery.
- **Network**: connection keepalive for stability and retry logic with exponential backoff. {% include tag.html v="2.0.0" %} A watchdog repairs connections that make no progress for 2 minutes, and a non-blocking replacement for the send semaphore removes a potential thread-starvation deadlock.
- **File processing**: streaming transfer (no full file buffering), preservation of file attributes, and an optimized file parser. {% include tag.html v="2.0.0" %} File writes happen off the connection queue, application sizes are computed once per app on their own thread, and the app builds in Swift 6 language mode with complete concurrency checking.

## Development and build process

- **Build-time code generation**: the project uses GYB (Generate Your Boilerplate) to generate a build-unique identity (`BuildIdentity.generated.swift.gyb`) at each build. It runs during the Xcode build, and the identity is used so builds can't pair with each other.
- **Testing**: Xcode unit tests, SwiftLint for code quality, pre-commit hooks for code standards.
- **Distribution**: archive, sign with a Developer ID Application certificate, notarize, export and distribute through MDM or other channels. See [Sign, notarize & distribute]({{ '/sign-notarize-distribute/' | relative_url }}).

## Technical resources

- [CONTRIBUTING.md]({{ site.repo_url }}/blob/main/CONTRIBUTING.md)
- [MAINTAINERS.md]({{ site.repo_url }}/blob/main/MAINTAINERS.md)
- [CHANGELOG.md]({{ site.repo_url }}/blob/main/CHANGELOG.md)
