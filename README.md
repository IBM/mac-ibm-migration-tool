# IBM Data Shift

![License](https://img.shields.io/badge/license-Apache%202-1984E5)
![Swift version](https://img.shields.io/badge/swift-6.0-1984E5?logo=swift)
![Project version](https://img.shields.io/badge/version-2.0.0-1984E5)
![TLS](https://img.shields.io/badge/TLS-1.3-1984E5)
![macOS](https://img.shields.io/badge/macOS-15+-bright%20green)

## Overview

**IBM Data Shift** is a native macOS application designed to streamline the migration of user data from an old Mac to a new Mac. Built with SwiftUI, it provides an intuitive, guided experience for transferring files, applications, preferences, and settings over a direct peer-to-peer network connection.

<img alt="IBM Data Shift" src="images/readme_img.png" width="100%">

## Awards

<img width="60" height="60" alt="GlobeeTech_Silver" src="https://github.com/user-attachments/assets/453ccd88-d38b-4bd6-bbde-eab862187a07"/>  

[2026 Silver Globee® Awards for Techonology - Best Business Process Automation (BPA) Solution - Best of Category](https://globeeawards.com/2026-winners-technology/)

## As seen on

[JNUC 2024 Session 1077](https://www.youtube.com/watch?v=S_exJoiVb20)  
[University of Utah, MacAdmins Meeting, June 2025](https://stream.lib.utah.edu/index.php?c=details&id=13705)  

## Key Features

### 🚀 **Seamless Data Migration**
- Transfer user files, applications, preferences, and settings between Macs
- Support for both **Wi-Fi** and **Thunderbolt** direct connections
- Automatic peer-to-peer network discovery using Bonjour (DNS-SD)
- Real-time progress tracking with time estimation
- **Pause & resume** - pause from the source Mac, disconnect the devices, and resume later from the same point

### 🔒 **Enterprise-Ready**
- Integration with **Jamf Pro** for managed environments
- MDM enrollment verification and environment detection
- Automated inventory updates post-migration
- Configurable via MDM profiles (UserDefaults)

### 🛡️ **Secure Pairing**
- Device-to-device transport secured with **TLS 1.3**, using an ephemeral, in-memory-only certificate
- Verification code exchange authenticated at the application layer with a CPace-style PAKE bound to the TLS channel, resistant to relay/man-in-the-middle attacks
- Destination device must explicitly accept or decline each incoming pairing request before its code can be used
- Automatic lockout after repeated incorrect verification code attempts
- Received paths and symbolic links are validated, so a migration can only write inside the user's home folder and `/Applications`

### ⚙️ **Highly Customizable**
- Extensive configuration options through UserDefaults
- Custom branding support (organization name, icons, colors)
- Configurable file inclusion/exclusion rules
- Flexible duplicate file handling policies
- Optional Terms & Conditions acceptance flow
- **Customizable Migration Presets** - replace the built-in Lite/Complete options with your own named bundles of categories and paths

### 📊 **Advanced File Management**
- Intelligent file discovery with customizable filters
- **Automatic app support file discovery** - migrates Application Support, Containers, Group Containers, Preferences, and more
- **Granular preferences migration** - discover and selectively migrate macOS system preferences (Dock, Finder, Keyboard, Trackpad, Accessibility, and more) by category
- Support for symbolic links preservation
- Duplicate file detection and handling
- Optional migration report generation
- Memory-optimized for large data transfers

### 🌍 **Localization Support**
- Multi-language support via `Localizable.xcstrings`
- Accessible UI with comprehensive VoiceOver support

## System Requirements

- **macOS**: 12.0 (Monterey) or later
- **Swift**: 6.0 or later (complete concurrency checking)
- **Xcode**: 16.0 or later (for building from source)
- **Network**: Wi-Fi or Thunderbolt connection between devices
- **Permissions**: Full Disk Access required for complete data migration

## How It Works

1. **Device Discovery**: Launch the app on both the source (old) and destination (new) Mac
2. **Connection**: Devices automatically discover each other over the local network
3. **Verification**: Destination device accepts the incoming pairing request, then both devices confirm a verification code over a TLS 1.3 encrypted channel
4. **Configuration**: Choose migration options (Lite, Complete, or Advanced)
5. **Transfer**: Files are transferred directly between devices with real-time progress
6. **Completion**: Optional post-migration steps (Apple ID verification, Jamf recon, device restart)

## Installation

### Pre-built Release
Download the latest release from the [Releases](../../releases) page.

### Building from Source

1. Clone the repository:
```bash
git clone https://github.com/IBM/mac-ibm-migration-tool.git
cd mac-ibm-migration-tool
```

2. Open the project in Xcode:
```bash
open migrator.xcodeproj
```

3. Build and run:
   - Select the `migrator` scheme
   - Choose your target device
   - Press `Cmd + R` to build and run

## Configuration

IBM Data Shift can be extensively configured via MDM profiles or local UserDefaults. Key configuration options include:

### Basic Settings
- `orgName`: Organization name for branding (default: "IBM")
- `networkServiceIdentifier`: Bonjour service identifier (default: "_migrator")
- `skipMDMCheck`: Skip device management verification (default: false)

### Migration Behavior
- `duplicateFilesHandlingPolicy`: How to handle duplicate files (`skip`, `replace`, `move`)
- `backupPath`: Path for duplicate file backups (default: "~/Desktop/Migration.Backup")
- `skipDeviceReboot`: Skip post-migration reboot prompt (default: false)
- `generateReport`: Generate migration report on desktop (default: false)
- `migrateAppSupportFiles`: Discover, display, and migrate app support files (Application Support, Containers, Preferences) (default: true)
- `migratePreferences`: Discover, display, and migrate macOS system preferences (default: true)
- `migrationPresets`: Array replacing the built-in `Lite`/`Complete` options with admin-defined presets, each with an `id`, `name`, `categories` (`desktop`, `documents`, `userFolder`, `apps`, `preferences`), and optional `additionalPaths`
- `excludeApplicationsFolder`: Completely exclude all Applications folders (`/Applications`, `~/Applications`, `/System/Applications`) from migration regardless of the selected preset or Advanced option. Enforced both during option setup and at the file-scanner level, so a full user-folder preset cannot bring them back (default: false)

### File Filtering
- `excludedPathsList`: Array of paths to exclude from migration
- `allowedPathsList`: Array of paths to explicitly include
- `excludedFileExtensions`: Array of file extensions to skip
- `excludedFilePrefixes`: Array of file name prefixes to skip

### Jamf Integration
- `mdmEnvironments`: Array of managed environments with server URLs and recon policy IDs
- `skipJamfRecon`: Skip Jamf inventory update (default: false)
- `jamfReconMethod`: Method for running recon (`selfServicePolicy` or `binary`)
- `storePath`: Path to Jamf Self Service app (must be an absolute path to an existing `.app` bundle, otherwise the default is used)

### UI Customization
- `welcomePageIcon`: Custom icon for welcome page
- `browserPageIcon`: Custom icon for browser page
- `setupPageIcon`: Custom icon for setup page
- Custom icons available for all app pages

For detailed configuration options, check project's [wiki](../../wiki).

## Usage

### For End Users

1. **Prepare both Macs**:
   - Ensure both devices have Wifi ON or connected via Thunderbolt
   - Grant Full Disk Access to the app when prompted
   - Keep both devices powered and awake during migration

2. **Launch the app** on both the source and destination Mac

3. **Follow the guided workflow**:
   - Device discovery and pairing
   - Migration option selection
   - File transfer with progress tracking
   - Post-migration steps (if configured)

### For Administrators

Deploy the app via your MDM solution with a configuration profile containing your desired settings. Example profile keys:

```xml
<key>orgName</key>
<string>Your Organization</string>
<key>skipMDMCheck</key>
<false/>
<key>duplicateFilesHandlingPolicy</key>
<string>move</string>
```

See the [wiki](../../wiki/App-Custom-Settings) for detailed deployment guides and configuration examples.

## Architecture

The app is built with a modular architecture:

- **SwiftUI Views**: Modern, declarative UI components
- **Network Layer**: Custom protocol over Network.framework for peer-to-peer communication
- **Migration Controller**: Orchestrates the file transfer process
- **Device Management**: Integration with macOS MDM APIs
- **Logging**: Comprehensive logging system with configurable verbosity

Key components:
- [`MigrationController.swift`](migrator/Controllers/MigrationController.swift): Core migration logic
- [`NetworkBrowser.swift`](migrator/Controllers/NetworkControllers/NetworkBrowser.swift): Device discovery
- [`NetworkServer.swift`](migrator/Controllers/NetworkControllers/NetworkServer.swift): Server-side networking
- [`NetworkConnection.swift`](migrator/Controllers/NetworkControllers/NetworkConnection.swift): Client-side networking
- [`EphemeralTLSIdentity.swift`](migrator/Controllers/NetworkControllers/EphemeralTLSIdentity.swift): In-memory-only TLS 1.3 server identity for pairing
- [`PairingAuthenticator.swift`](migrator/Controllers/NetworkControllers/PairingAuthenticator.swift): CPace-style PAKE used to verify the pairing code at the application layer
- [`PreferencesDiscovery.swift`](migrator/Controllers/PreferencesDiscovery.swift): Discovery, read, and write of macOS system preferences
- [`AppContext.swift`](migrator/AppContext.swift): Centralized configuration management

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details on:
- Code of conduct
- Development workflow
- Pull request process
- Coding standards

### Quick Start for Contributors

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests and SwiftLint
5. Commit your changes (`git commit -am 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## Security

For security concerns, please see our [Security Policy](docs/SECURITY.md).

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a detailed history of changes and releases.

## Support

- **Issues**: Report bugs or request features via [GitHub Issues](../../issues)
- **Community**: Join the `#mac-ibm-open-source` channel in the [MacAdmins Slack](https://www.macadmins.org)
- **Maintainers**: See [MAINTAINERS.md](MAINTAINERS.md) for contact information

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

All source files must include the following copyright and license header:

```text
//
// © Copyright IBM Corp. 2023, 2026
// SPDX-License-Identifier: Apache2.0
//
```

## Acknowledgments

- Built by the Mac@IBM team
- Powered by Apple's Network.framework for peer-to-peer connectivity
- Designed for enterprise macOS environments

---

**Note**: This tool is specifically designed for macOS environments and requires appropriate permissions for full functionality. Always test in a non-production environment before deploying to end users.
