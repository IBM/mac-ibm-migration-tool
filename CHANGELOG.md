# Changelog

All notable changes to this project will be documented in this file.

## [2.0.0] - 2026-11-10

### Device Pairing & Security
**Enhancements**
* Migrated the device pairing/transfer channel from TLS 1.2 to TLS 1.3. Since TLS 1.3 removed Network.framework's external-PSK mode, the destination Mac now serves an ephemeral, in-memory-only self-signed certificate (never written to the keychain) purely to get an encrypted, forward-secret transport.
* Peer verification now happens at the application layer via a CPace-style password-authenticated key exchange (PAKE), derived from the 6-digit pairing code and bound to the TLS channel's exporter secret. This prevents a relay/man-in-the-middle attack even from an attacker holding valid TLS certificates on both legs of the connection.
* The destination Mac must now explicitly accept or decline each incoming pairing request before its verification code can be used, rather than displaying the code to any device that discovers it on the network.
* Repeated incorrect verification code attempts now lock pairing on the destination device until a new code is generated, mitigating brute-force guessing of the 6-digit code.

### Migration Security
**Enhancements**
* The destination Mac now validates every path and symbolic link received from the source: unknown sources, absolute or `..`-containing paths, and anything resolving (through existing or dangling symlinks) outside the user's home folder and `/Applications` are refused.
* Received file attributes are reduced to permission bits (without setuid/setgid/sticky) and dates; ownership and flags from the peer are ignored.
* Jamf Self Service is now launched with `/usr/bin/open` via an argument vector instead of an AppleScript shell command, so no value is ever parsed by a shell.
* The `storePath` setting (and Jamf's `self_service_app_path`) is now only honored if it is an absolute path to an existing `.app` bundle without control characters; managed Jamf values must be forced by a configuration profile.

**Bug Fixes**
* Fixed files with read-only permissions, and directories whose owner access came only from an ACL (e.g. `~/Public`), failing to be written on the destination.
* Fixed app support files located in otherwise-excluded folders (e.g. `~/Library`) being skipped even though discovery had selected them; files that cannot be scanned are now listed in the migration report.
* Fixed the file count of the selection not being updated when files, apps or preferences are selected or deselected.

### Migration
**Enhancements**
* **Pause & Resume**: The source Mac can now pause a running migration, finishing the in-flight data first so the devices can be disconnected (e.g. to move or sleep them). The destination keeps its state and automatically accepts the source's reconnection when the migration is resumed, continuing from the same point. A resume that cannot reach the destination within 60 seconds returns to the paused screen so it can be retried.
* Items that exist only as placeholders (dataless files and folders, e.g. iCloud Drive items removed by "Optimize Mac Storage") are no longer read during a migration, so they are not downloaded from the cloud on the source Mac; they are skipped and logged.
* Cache and temporary folders that apps regenerate on their own (`Library/Caches` in the user library, Containers and Group Containers, and a container's `Data/tmp`) are no longer migrated, reducing transfer size and time. This also applies to app support files.

**Bug Fixes**
* Fixed the exclusion rules (excluded file extensions and name prefixes, such as a nested `node_modules`, `.DS_Store` or VM disk images) only being applied to the first levels of a selected folder: they are now applied at every depth, and sizes and file counts match what is actually transferred. As a result, matching items deeper inside a selected folder are no longer migrated. Application bundles (`.app`) are always copied whole, so an app's own `node_modules` or cache folders are never removed.
* Fixed the app freezing on the source Mac during the migration of an application's support files when they contain named pipes (e.g. the `*.cv` and `*.note` pipes of Realm databases): opening a named pipe for reading blocks forever. Named pipes, sockets and device files are now skipped and logged.
* Fixed scanning an app's support files running on the main thread, which made the interface unresponsive while large folders were being listed.
* Fixed large read-only files (e.g. Git `*.pack` files) failing to be written on the destination Mac when they are transferred in several parts.
* Fixed the size calculation of applications occupying the threads shared by all background tasks, which could make it extremely slow or appear to never finish on Macs with many large applications; each application is now measured in a single pass on its own thread.

### User Interface
**Enhancements**
* Adopted the Liquid Glass effect conditionally on supported macOS versions, falling back to the previous appearance elsewhere.

### Preferences Migration
**Enhancements**
* **Granular Preferences Selection**: Data Shift now discovers macOS system preferences on the source Mac - grouped into categories such as Dock, Finder, Keyboard, Trackpad/Mouse, Appearance, Accessibility, Language & Region, Menu Bar/Control Center, Sound Effects, Screenshots, Screen Saver, Terminal, Mission Control, Stage Manager, Keyboard Shortcuts, and Hot Corners - and lets users review and individually select which groups to migrate.
* Each preference group shows a human-readable description of exactly which settings it carries, plus the number of discovered keys and estimated payload size.
* Preference values are read and written through `CFPreferences` instead of copying `.plist` files directly, so migrated values reflect `cfprefsd`'s live cache, and existing values on the destination are backed up before being overwritten.
* Preferences migration can be toggled independently via the new `migratePreferences` managed setting.

### Migration Setup
**Enhancements**
* **Customizable Migration Presets**: Administrators can now replace the built-in `Lite`/`Complete` options with their own named presets - combining categories (Desktop, Documents, full user folder, Applications, Preferences) and additional custom paths - via the new `migrationPresets` managed setting.
* Automatic app support file discovery and migration can now be toggled independently via the new `migrateAppSupportFiles` managed setting.
* The Recap screen now shows the same expandable, per-app support file breakdown (categories and counts) already available in the Advanced Selection view.
* Administrators can now completely exclude the Applications folder from migration — regardless of what a preset or the Advanced option includes — via the new `excludeApplicationsFolder` managed setting (default: `false`). The exclusion covers all Applications folder locations (`/Applications`, `~/Applications`, `/System/Applications`) and is enforced both during migration option setup (no apps are loaded) and at the file-scanner level (the folders are added to the URL exclusion list), so they cannot enter through a full user-folder preset either.

### Application Migration
**Enhancements**
* **Automatic App Support File Discovery**: Data Shift now automatically discovers and migrates all application-related support files including:
  - Application Support folders
  - Sandboxed Containers
  - Group Containers
  - Preference files (.plist)
* **Enhanced UI**: Advanced Selection view now displays discovered support files per app with expandable disclosure groups showing file categories and counts
* **Performance Optimization**: Implemented FileSizeCache for efficient size calculations, reducing redundant operations by 58%

### Performance & Reliability
**Enhancements**
* File discovery now caches directory listings shared across apps (Application Support, Containers, Group Containers, Preferences), avoiding redundant disk scans when discovering support files for many apps in the same session.
* Group Container matching now also inspects shared, vendor-wide containers (e.g. a single Office container shared by every Microsoft app) one level deeper for an app-specific subfolder, instead of migrating the entire shared container when a more precise match exists.
* Added a connection-health watchdog that detects when the network connection stops making progress (no throughput for 2 minutes, or a message that exhausts all of its send retries) and automatically attempts to repair the connection, instead of letting the migration silently stall or repeatedly retry subsequent items against a dead connection.
* Writing received files and file chunks to disk during migration now happens off the network connection's queue, so a slow or unresponsive destination volume can no longer delay delivery of connection state and keepalive events.
* Replaced the internal semaphore used to limit concurrent network send operations with a non-blocking implementation, removing a potential thread-starvation deadlock under concurrent load.
* Adopted Swift 6 language mode with complete concurrency checking across the app, compiler-enforced to eliminate data races.

**Bug Fixes**
* Fixed an issue where a circular symbolic link encountered during migration could permanently stop the destination device from processing any further incoming data, silently stalling the migration with no error shown.
* Fixed a tight retry loop that could flood the log with repeated network receive errors (and contend with an in-progress reconnection attempt) during the brief window after a connection drops but before Network.framework reports it as failed.

### Accessibility
**Enhancements**
* Improved Dynamic Type support, VoiceOver hints, and high-contrast appearance across the app's views.

### Logging
**Enhancements**
* Standardized and categorized internal logging (e.g. Migration, Network, Pairing, Discovery, Report, Device) for clearer filtering in Console.app, and reduced excessive log verbosity.

### General Updates
**Bug Fixes**
* Fixed a typo in the setup instructions localized label.

## [1.4.1] - 2026-05-07

### General Updates
**Bug Fixes**
- The parsing of URLs from the Configuration Profile now accurately identifies regex patterns within the path components.
- The check for destination device storage capacity has been made optional if the necessary data from the destination device is missing.

## [1.4.0] - 2026-02-20

### General Updates
**Enhancements**
* New Welcome screen with actionable buttons.
* New scrolling text areas for files with long name.
**Bug Fixes**
* Resolved an issue that could cause the app to unexpectedly quit on the old device during the migration process.
* Resolved a bug that could cause the migration logic to stall.
* Resolved a bug that could cause the missing migration of part of an application bundle.

### Device Pairing
**Enhancements**
* Enabled a scheduled check for Local Network access when the device is being discovered.

### Migration Setup
**Enhancements**
* Data Shift now checks the compatible architecture for the applications in scope of the migration and provides the user with an option to ignore, review, or migrate those. 
* Improved the UI that represent the migration options.

### Configuration
**Enhancements**
* It’s now possible to use regular expressions in the path components of URLs added to the URLExclusionList and AllowList.

## [1.3.0] - 2025-11-05

### Device Connection
**Enhancements**
* Added recovery logic for network connection issues.
* Enhanced security measures for network connections.

### Migration
**Enhancements**
* Improved localization for migration view.
**Bug Fixes**
* Fixed unexpected crash during migration process.
* Fixed issue where file attributes were being replaced by system during migration. 
* Fixed file allowlisting and exclusion logic.

### General Updates
**Enhancements**
* Implemented comprehensive migration report generation feature. 
* New optional page showing migration summary before starting the migration process. 
* Completely reworked file discovery logic for improved performance and reliability.
* Optimized file parser for better performance.
* Revised device management check logic.
* Added support for Liquid Glass on macOS Tahoe.
* Improved logging for device management checks.
* Updated application icon.
* Added missing documentation for various components.

**Bug Fixes**
* Implemented language corrections in localization strings. 
* Fixed cleanup phase for user defaults.

### Customization
**Enhancements**
* Added support for customizable icons on each page via UserDefaults configuration. 
* Added optional information view on the Welcome page that can be toggled via configuration.
* Added support for Privacy Policy, Terms & Conditions, and Third Party Notices.
* Added optional Terms & Conditions acceptance view and welcome view integration.

## [1.2.1] - 2025-06-15

### App Configuration
**Improvements**
* The variable base path construction for the excludedPathsList and allowedPathsList configuration profile keys has been enabled. This allows admins to define the base path of URLs they want to exclude or allow using $HOMEFOLDER and $APPFOLDER. If the tag is missing, the app will automatically consider the user’s home folder as the base path.

## [1.2.0] - 2025-06-11

### Device Connection
**Improvements**
* New automatic connection recovery logic;
* Enabled full peer to peer communications between devices (devices don't need to be on the same network);
**Bug Fixes**
* Resolved a bug that caused unexpected drop of the connection between devices right after the connection establishment;

### Performances
**Improvements**
* Optimised memory consumption, now the app use between 90 and 95% less RAM;
* Optimised file discovery;

### Accessibility
**Improvements**
* Improved accessibility labels and hints;

### App Configuration
**Improvements**
* Expanded the set of configurable keys.

### General Updates
**Bug Fixes**
* Resolved a bug that caused the wrong appearance of the menu bar items;
* Resolved a bug that caused the wrong representation of files;
* Resolved a bug that allowed the user to quit the app bypassing the quit alert;
* Resolved some typos in the app texts;

## [1.1.0] - 2024-10-17

* This is the first release of the project. Please check the Wiki to know more about IBM Data Shift!

---

[1.4.0]: https://github.com/IBM/mac-ibm-migration-tool/releases/tag/v-1.4.0-b-214
[1.3.0]: https://github.com/IBM/mac-ibm-migration-tool/releases/tag/v-1.3.0-b-172
[1.2.1]: https://github.com/IBM/mac-ibm-migration-tool/releases/tag/v-1.2.1-b-130
[1.2.0]: https://github.com/IBM/mac-ibm-migration-tool/releases/tag/v-1.2.0-b-121
[1.1.0]: https://github.com/IBM/mac-ibm-migration-tool/releases/tag/v-1.1.0-b-100
