---
layout: default
title: PPPC profile
permalink: /pppc-deployment/
---

For **IBM Data Shift** to work properly it requires Full Disk Access, plus access to the Documents, Desktop and Downloads folders. The best way to grant these permissions is a Privacy Preferences Policy Control (PPPC) payload deployed through a configuration profile.

The app needs the following permissions:

- **SystemPolicyDesktopFolder**
- **SystemPolicyDocumentsFolder**
- **SystemPolicyDownloadsFolder**
- **SystemPolicyAllFiles**

Example:

<img src="{{ '/assets/images/PPPC.png' | relative_url }}" alt="PPPC Example" width="80%">

The **Code Requirement** field depends on the certificate used to sign the app. To get its value, run `codesign -dr - /path/to/Application.app` on your build of IBM Data Shift and copy everything after `designated => `.

You can deploy a single configuration profile that contains both the PPPC payload and the [custom settings]({{ '/custom-settings/' | relative_url }}).

The app also needs **Local Network** access to discover the other device. macOS asks the user for this on first launch.

## Additional resources

- [Apple: Privacy Preferences Policy Control MDM payload settings for Apple devices](https://support.apple.com/en-gb/guide/deployment/dep38df53c2a/web)
