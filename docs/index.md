---
layout: default
title: Home
permalink: /
---

# IBM Data Shift

**Current version: {{ site.app_version }}**

IBM Data Shift is a native macOS app that migrates files, applications and preferences from an old Mac to a new one over a direct, encrypted peer-to-peer connection. This site explains how to use it and how to customize, sign and deploy your own instance.

## What's new

### v2.0.0 {% include tag.html v="2.0.0" %}

- **Stronger pairing and transport**: TLS 1.3 with forward secrecy, a PAKE-based peer verification bound to the TLS session, explicit accept/decline of pairing requests on the new Mac and a lockout after repeated wrong codes. See [Security & privacy]({{ '/security/' | relative_url }}).
- **Safer transfers**: the new Mac validates every path, symlink and file attribute it receives, and Jamf Self Service is launched without a shell.
- **Pause & resume**: the old Mac can pause a running migration and resume it later from the same point.
- **Granular preferences migration**: macOS preferences are discovered in groups (Dock, Finder, Keyboard, ...) that users review and select individually. Toggle with `migratePreferences`.
- **Customizable presets**: replace Lite/Complete with your own named presets through `migrationPresets`.
- **More admin control**: `migrateAppSupportFiles` and `excludeApplicationsFolder` settings.
- **Smarter scanning**: app support files are discovered automatically, exclusion rules apply at every depth, caches and dataless (cloud-only) items are no longer migrated.
- **Reliability**: connection-health watchdog, many fixes for stalls, freezes and write failures, Swift 6 concurrency.
- **UI and accessibility**: conditional Liquid Glass, better Dynamic Type, VoiceOver and high contrast, categorized logging.

Full changelog and earlier releases are listed in the [CHANGELOG]({{ site.repo_url }}/blob/main/CHANGELOG.md).

## Get started

Follow these steps to deploy your customized instance of IBM Data Shift.

### 1. Learn the standard workflow
Read [Using IBM Data Shift]({{ '/user-guide/' | relative_url }}) to see how the migration looks for end users.

### 2. Rebrand the app
Customize the app name, bundle identifier, icons and a few other details. See [Rebrand the app]({{ '/rebranding/' | relative_url }}).

### 3. Customize the behavior
The main migration workflow is fixed, but startup checks, post-migration steps, the migration scope and the UI are configurable.

| What | Where |
|------|-------|
| All configuration keys, deployable through a configuration profile | [Custom settings]({{ '/custom-settings/' | relative_url }}) |
| Startup MDM check and Jamf inventory update | [MDM check & inventory update]({{ '/mdm-check/' | relative_url }}) |
| Terms & Conditions acceptance, privacy policy and third party notices links | [Custom settings]({{ '/custom-settings/#terms--conditions' | relative_url }}) |
| Custom page icons, welcome page information, migration summary page | [Custom settings]({{ '/custom-settings/#user-interface-customization' | relative_url }}) |

#### Migration options and scope

- **Lite**: only the Desktop and Documents folders are migrated.
- **Complete**: all applications, user preferences and the entire User folder are migrated. Of the **Library** folder, only **Application Support** and **Preferences** are included.
- **Advanced Selection**: users manually select what to migrate from the files and applications included in the Complete option.
- **Custom presets** {% include tag.html v="2.0.0" %}: administrators can replace Lite and Complete with their own presets, see [Custom settings]({{ '/custom-settings/#migration-presets' | relative_url }}).

Four lists in `AppContext.swift` control what the scan includes. They can be extended at runtime through the configuration profile (see [Custom settings]({{ '/custom-settings/#file-exclusion-strategy' | relative_url }})):

- `defaultUrlExclusionList`: local paths excluded from the scan.
- `defaultExplicitAllowList`: paths explicitly included. A subpath of an excluded path that is in this list is still migrated.
- `defaultExcludedFileExtensions`: file extensions excluded from the scan.
- `defaultExcludedFilePrefixes`: file name prefixes excluded from the scan.

Including large directories can significantly slow down the pre-migration scan and increase memory usage.

### 4. Archive, sign and notarize
See [Sign, notarize & distribute]({{ '/sign-notarize-distribute/' | relative_url }}).

### 5. Distribute the app
IBM Data Shift requires Full Disk Access. Deploy a PPPC profile to avoid repeated prompts, see [PPPC profile]({{ '/pppc-deployment/' | relative_url }}). You can deploy a single profile containing both the custom settings and the PPPC payload.

## For technical teams and security reviewers

- [Architecture overview]({{ '/architecture/' | relative_url }}): components, data flow and build process.
- [Security & privacy]({{ '/security/' | relative_url }}): transport security, pairing, validation, threat model and privacy.
