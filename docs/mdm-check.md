---
layout: default
title: MDM check & inventory update
permalink: /mdm-check/
---

At startup, IBM Data Shift can run a background check to verify that the device is enrolled in a recognized MDM program. To enable it, set the custom setting `skipMDMCheck` to `false` as described in [Custom settings]({{ '/custom-settings/' | relative_url }}). Some variables in `AppContext.swift` must also be customized before archiving the project.

To recognize your MDM environment:

1. Define a new `ManagedEnvironment` object in the `mdmEnvironments` array in `AppContext.swift`. Each environment needs a `name` (nr. 1 in the picture below) and a `ServerURL` (nr. 2). The ServerURL identifies the environment by matching the ServerURL of the MDM profile detected on the device.
2. If the app is configured to check the device management state and no recognized environment is found, it prompts the user to visit a website to start enrollment. Define this URL in the `enrollmentRedirectionLink` variable (nr. 5) in `AppContext.swift`.
3. **If you use** `selfServicePolicy` as the `jamfReconMethod`, also define the `reconPolicyID` (nr. 3) for that environment and the `storePath` variable (nr. 4).

These values are also available as [custom settings]({{ '/custom-settings/' | relative_url }}) deployable through a configuration profile.

<div class="note">{% include tag.html v="2.0.0" %} The <code>storePath</code> value (and Jamf's <code>self_service_app_path</code>) is only honored if it is an absolute path to an existing <code>.app</code> bundle without control characters. Self Service is launched without a shell. Managed Jamf values must be forced by a configuration profile.</div>

<img src="{{ '/assets/images/MDMCheck/mdm-check-1.png' | relative_url }}" alt="MDM Check Example" width="100%">
