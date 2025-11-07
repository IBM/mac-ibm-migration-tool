# Changelog

All notable changes to this project will be documented in this file.

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
* Fixed issue where file attributes were being replaced by system during migration. #50
* Fixed file allowlisting and exclusion logic.

### General Updates
**Enhancements**
* Implemented comprehensive migration report generation feature. #20
* New optional page showing migration summary before starting the migration process. #39 #27 #33
* Completely reworked file discovery logic for improved performance and reliability.
* Optimized file parser for better performance.
* Revised device management check logic.
* Added support for Liquid Glass on macOS Tahoe.
* Improved logging for device management checks.
* Updated application icon.
* Added missing documentation for various components.

**Bug Fixes**
* Implemented language corrections in localization strings. #49
* Fixed cleanup phase for user defaults.

### Customization
**Enhancements**
* Added support for customizable icons on each page via UserDefaults configuration. #48
* Added optional information view on the Welcome page that can be toggled via configuration.
* Added support for Privacy Policy, Terms & Conditions, and Third Party Notices.
* Added optional Terms & Conditions acceptance view and welcome view integration.

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
* Expanded the set of configurable keys (see [wiki](https://github.ibm.com/Mac-At-IBM/migration-tool/wiki/App-Custom-Settings));

### General Updates
**Bug Fixes**
* Resolved a bug that caused the wrong appearance of the menu bar items;
* Resolved a bug that caused the wrong representation of files;
* Resolved a bug that allowed the user to quit the app bypassing the quit alert;
* Resolved some typos in the app texts;

## [1.1.1] - 2024-11-22

### Enhancements
* Now the environment check only verifies the host part of the URL to avoid false negatives caused by different ServerURLs used in the same environment. #29

## [1.1.0] - 2024-10-17

### General
**Enhancements**
* Improved Wiki with new Images.
* New customisable policy for handling duplicate files.
* Removed useless entries from App Menu.
* App renamed Mac@IBM Data Shift.
* New customisable option for Jamf recon execution.
* Improved branding customisation.

## [1.0.0] - 2024-09-05

### General Updates
**Enhancements**
* Enhanced dynamic power source detection with an alert pop-over notification.
* Added Outlook profile location to the migration list.
* Expanded the list of ignored files to include VM disks, preventing false positives during file scans.
* Improved overall app stability.
* Added a confirmation alert when quitting the app.
* Implemented safeguards to prevent multiple instances of the app from running simultaneously.
**Bug Fixes**
* Fixed an issue where the directory content view header was not displaying correctly.

### Browser View
**Enhancements**
* Added a new label reminding users to run the app on both devices.
* Improved the stability of the Network Browser.
* Devices now display only the available preferred communication technology (Wi-Fi or Thunderbolt).

### Server View
**Enhancements**
* Improved body text clarity.
* Enhanced server stability.
**Bug Fixes**
* Fixed an issue where multiple instances of the same device appeared as discoverable after a server restart.

### Migration Setup View
**Enhancements**
* Added a "Select All" checkbox to the Advanced Migration option.
**Bug Fixes**
* Fixed an issue where the "Start Migration" button remained disabled even when a migration option was selected.

### Migration View
**Enhancements**
* Displayed the connection technology next to the connected device name.
* Added time estimation for migration completion under the progress bar.
* Improved the accuracy of completion percentage calculations.
* Enhanced text visibility during and after migration.
* Added an alert to notify users about preventing device sleep during migration.
* Added an alert to warn users about file tampering during migration.
* Device sleep is now prevented only during the migration phase.

### Apple ID Check View
**Enhancements**
* Introduced a new conditional view guiding users through Apple ID login on Mac.

### Device Restart View
**Enhancements**
* Added a new conditional view notifying users when a device restart is required.
* Implemented new logic to install and remove a Launch Agent, allowing the app to re-run after a reboot.

### Final View
**Enhancements**
* Introduced a new summary view of the migration, with automatic Inventory Update.
* Improved the logic for the Inventory Update process via the Mac@IBM App Store.
* Added a warning text to notify users about file checks before deletion.

---

[1.3.0]: https://github.ibm.com/Mac-At-IBM/migration-tool/releases/tag/v-1.3.0-b-170
[1.2.0]: https://github.ibm.com/Mac-At-IBM/migration-tool/releases/tag/v-1.2.0-b-121
[1.1.1]: https://github.ibm.com/Mac-At-IBM/migration-tool/releases/tag/v-1.1.1-b-106
[1.1.0]: https://github.ibm.com/Mac-At-IBM/migration-tool/releases/tag/v-1.1.0-b-103
[1.0.0]: https://github.ibm.com/Mac-At-IBM/migration-tool/releases/tag/v-1.0.0-b-92