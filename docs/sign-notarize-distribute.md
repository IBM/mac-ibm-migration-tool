---
layout: default
title: Sign, notarize & distribute
permalink: /sign-notarize-distribute/
---

To distribute the app you need to:

- Change the app bundle identifier
- Archive it
- Sign it
- Send it to the Apple notarization service
- Export it for distribution

Xcode makes this process quick. Here is how it looks.

## What you need

- An **Apple ID** enrolled in your company's **Apple Developer Enterprise Program**
- The latest **Xcode** (available on the [App Store](https://apps.apple.com/app/xcode/id497799835?mt=12))
- Your team's **Developer ID Application** certificate installed in your Keychain

## The steps

1. If you haven't yet, [rebrand the app]({{ '/rebranding/' | relative_url }}). This is mandatory.
2. Archive the app: **Product** → **Archive**.

   <img src="{{ '/assets/images/Distribution/sign-notarize-1.png' | relative_url }}" width="80%">

3. When the archive completes, the **Organizer** window lists the archives of your app. Select the latest one and click **Distribute App**.

   <img src="{{ '/assets/images/Distribution/sign-notarize-2.png' | relative_url }}" width="80%">

4. Choose **Direct Distribution**.

   <img src="{{ '/assets/images/Distribution/sign-notarize-3.png' | relative_url }}" width="80%">

5. Click **Distribute** and wait until it finishes.
6. Wait for the Apple notarization service to complete its checks. When done, the archive in the Organizer shows the **Ready to distribute** status.
7. Click **Export Notarized App** to save the signed and notarized app locally. It is now ready to distribute.

   <img src="{{ '/assets/images/Distribution/sign-notarize-4.png' | relative_url }}" width="80%">

After distributing, deploy a [PPPC profile]({{ '/pppc-deployment/' | relative_url }}) so users aren't prompted for file access.

## Apple documentation

- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/xcode/notarizing_macos_software_before_distribution)
- [Resolving common notarization issues](https://developer.apple.com/documentation/xcode/notarizing_macos_software_before_distribution/resolving_common_notarization_issues)
- [Create, export, and delete signing certificates](https://help.apple.com/xcode/mac/current/#/dev154b28f09)
- [Upload a macOS app to be notarized](https://help.apple.com/xcode/mac/current/#/dev88332a81e)
