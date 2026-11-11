---
layout: default
title: Default Configuration Settings of the Public Release
permalink: /public-release-defaults/
---

This document outlines the default configuration of the IBM Data Shift public release binary. These settings represent how the application is configured out-of-the-box before any MDM customization.

## Default Configuration Settings

### Organization & Branding

| Setting | Default Value | Description |
|---------|---------------|-------------|
| `orgName` | `"IBM"` | Organization name displayed throughout the app |
| `customFontFamily` | `"IBMPlexSans"` | Custom font family (IBM Plex Sans included) |

### Network Configuration

| Setting | Default Value | Description |
|---------|---------------|-------------|
| `networkServiceIdentifier` | `"_migrator"` | Bonjour service identifier for device discovery |
| Bonjour Service | `_migrator._tcp` | DNS-SD service type (configured in Info.plist) |

### Device Management

| Setting | Default Value | Description |
|---------|---------------|-------------|
| `skipMDMCheck` | `true` | MDM enrollment verification is **disabled** by default |
| `mdmEnvironments` | `[]` | No managed environments configured |
| `enrollmentRedirectionLink` | `""` | No enrollment redirection URL set |

### Post-Migration Workflow

| Setting | Default Value | Description |
|---------|---------------|-------------|
| `skipAppleIDCheck` | `true` | Apple ID verification step is **skipped** |
| `skipJamfRecon` | `true` | Jamf inventory update is **skipped** |
| `jamfReconMethod` | `selfServicePolicy` | Method for Jamf recon (when enabled) |
| `skipDeviceReboot` | `false` | Reboot prompt is **shown** after migration |
| `storePath` | `""` | No custom Jamf Self Service path configured |

### File Handling

| Setting | Default Value | Description |
|---------|---------------|-------------|
| `duplicateFilesHandlingPolicy` | `move` | Duplicate files are moved to backup folder |
| `backupPath` | `~/Desktop/Migration.Backup` | Location for backed-up duplicate files |
| `generateReport` | `true` | Migration report is **generated** on desktop |
| `validateAppsArchitecture` | `true` | App architecture compatibility check is **enabled** |

### User Interface

| Setting | Default Value | Description |
|---------|---------------|-------------|
| `shouldRequireTAndCAcceptance` | `true` | Terms & Conditions acceptance is **required** |
| `skipMigrationSummary` | `false` | Migration summary view is **shown** |
| `showWelcomePageInfo` | `true` | Version/copyright/privacy info shown on welcome page |

### Legal Resources

| Setting | Default Value | Description |
|---------|---------------|-------------|
| `privacyPolicyURL` | `http://www.ibm.com/privacy` | IBM Privacy Policy URL |
| `termsConditionsURL` | `T&C.pdf` | Local Terms & Conditions PDF (bundled) |
| `thirdPartyNoticesURL` | `TPNotices.pdf` | Local Third Party Notices PDF (bundled) |

## Default File Exclusions

The public release includes these default exclusions during file discovery:

### Excluded Paths
- User Library directory (`~/Library`)
- The migration app itself
- Built-in Apple apps (Numbers, Pages, Keynote, Safari)
- System Utilities folder
- Xcode.app
- User Trash
- FileProvider support files
- Hidden directories (`.local`, `.cache`, `.cisco`)

### Excluded File Extensions
- `vdi` (Virtual disk images)
- `vbox` (VirtualBox files)
- `img` (Disk images)

### Excluded File Prefixes
- `MigrationReport_` (Previous migration reports)
- `~` (Temporary files)
- `.DS_Store` (macOS metadata)
- `.localized` (Localization files)
- `node_modules` (Node.js dependencies)

## Default Allowed Paths

These paths are explicitly included even if they fall under excluded directories:

- `~/Library/Application Support`
- `~/Library/Application Scripts`
- `~/Library/Preferences`

## Default Migration Options

The app provides three migration modes:

### Lite Mode
- **Included**: Desktop and Documents folders
- **Customizable**: No

### Complete Mode
- **Included**: Entire user home folder + all applications
- **Customizable**: No

### Advanced Selection Mode
- **Included**: All user files and applications
- **Customizable**: Yes (users can select/deselect individual items)

## Customization

All settings can be customized via MDM configuration profiles using UserDefaults keys. For detailed configuration options and deployment guides, see the [project wiki](../wiki/App-Custom-Settings).

## Notes

- This configuration is designed for **unmanaged environments** where users can migrate data without enterprise MDM requirements
- Organizations deploying via MDM should configure appropriate settings for their environment
- The app requires **Full Disk Access** permission for complete data migration
