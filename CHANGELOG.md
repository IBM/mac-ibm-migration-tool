# Changelog

All notable changes to this project will be documented in this file.

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
