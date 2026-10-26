# Roam v0.6 — Source review and targeted fixes

Reviewed the complete user-supplied `Roam_v0.5_iOS` archive, not just a file listing.

## Findings confirmed from the supplied project

- The archive contains the full SwiftUI frontend, `LocationEngine.swift`, `SpoofSession.swift`, the pairing and LocalDevVPN code, an Xcode project (`Locus.xcodeproj`), `project.yml`, the app icon, and a bundled `libidevice_ffi.a` native static library.
- The Swift source files passed the Swift **syntax parser** on Linux. `Info.plist`, the entitlements plist and JSON asset metadata are structurally readable. **No iOS/SwiftUI type checking or Xcode compilation has occurred.**
- A member of the bundled static library was identified as a Mach-O arm64 object. That does **not** guarantee the library will link successfully in a particular Xcode SDK.
- The on-disk Xcode target and project are still named `Locus`, while the **displayed app name** is `Roam`. This is an internal scheme name, not proof of a branding failure. Avoid renaming it before the first successful build.
- `LocationEngine.swift`, `SpoofSession.swift`, `PairingStore.swift`, on-device pairing, and the VPN callback logic are **unchanged** in this update. Wi-Fi-started location spoofing and 5G movement remain **unverified in Roam itself**.

## Five targeted source/project patches

1. `Locus/Support/Theme.swift`: replaces the optional iOS 26-only Liquid Glass helper with a system-material fallback. This removes a dependency on the iOS 26 SDK for that specific component without changing Roam's custom main-screen palette and controls. An Xcode version supporting the user's iOS release may still be needed for device testing.
2. `Locus/Support/LocalDevVPN.swift`: guards a nullable interface address before dereferencing it while reading VPN addresses, preventing a possible crash on unusual network interfaces.
3. `Locus/Features/Map/MapHomeView.swift`: searching for a place now updates **Recents** without silently adding that place to **Favourites**. The star button remains the explicit save action.
4. `Locus.xcodeproj/project.pbxproj`: sets version/build to **0.6.0 (6)** in the existing Xcode project.
5. `project.yml`: mirrors version/build **0.6.0 (6)** so regeneration with XcodeGen will not revert it.

## Remaining risks / not yet verified

- **Mac requirement:** Xcode/iOS SDK compilation, linking of the native `idevice` library, Apple signing and testing on the iPhone are still outstanding. Installing on iOS 27 may require an Xcode version that supports that OS/device.
- **Platform restrictions:** GPS simulation through developer services depends on Apple developer pairing and LocalDevVPN. The user's Locus experiments showed new teleports worked on Wi-Fi but failed on 5G, while continuing joystick movement worked on 5G after a Wi-Fi start. Roam has not yet demonstrated these behaviours.
- **VPN display:** a detected `10.7.*` VPN interface is not proof that the developer tunnel is usable.
- **Signing/entitlements:** the inherited `Locus.entitlements` includes manually specified debugging/network entitlements. Review the provisioning result in Xcode if signing fails; do not add restricted capabilities or assume App Store eligibility.
- **UI layout:** portrait screenshots, VoiceOver / accessibility, map search, safe areas and on-device joystick interaction must be tested on a physical phone.
- **Legacy identifiers:** internal class names, debug log labels, saved-preference keys, and the Xcode scheme still include `Locus`. These do not necessarily block a build; consider renaming them **after** the prototype builds.
- **Third-party licences:** retain `LICENSE` and review the bundled `idevice` library's notices before any redistribution.
- **Background operation:** inherited silent-audio keep-alive and location modes require particular care if pursuing App Store distribution; this prototype has not been reviewed for App Store policy compliance.

## What this update does not do

It does not solve 5G-only initial teleporting, add a new GPS engine, install an IPA, or establish build success. It preserves the known source baseline for Mac testing.
