# Roam v0.6 — First Mac/Xcode build

1. Copy the **entire** `Roam_v0.6_iOS` folder to the Mac, including `Vendor/idevice` and `LICENSE`. Do not rename or delete the bundled `.a` file.
2. Install an Xcode release that **supports the iOS version on the iPhone** (the test phone currently runs iOS 27). A Mac running an older system may not support the necessary Xcode release.
3. Open `Locus.xcodeproj` in Xcode. The internal project and scheme are called **Locus** for now; the intended installed app display name is **Roam**.
4. Choose the iOS app target → **Signing & Capabilities**, select your Apple development team and use a bundle identifier available to that team. If you change the bundle identifier, update `project.yml` too (and review matching pairing UTType IDs before regenerating the project).
5. Select the connected iPhone as the destination, then **Product → Build**. Do not assume a successful project generation equals a successful build.
6. If the build fails, save the **first full error message**, Xcode version, and whether the error involves Swift types, missing SDK symbols, signing, or the `idevice` native library. Avoid applying random signing entitlements.
7. If it builds, install the app on the iPhone and check that the **Roam** icon/name, search and map, favourites, and joystick interface appear as expected. Developer pairing may have to be performed separately for the Roam bundle ID.
8. With Wi-Fi enabled, test a short teleport and verify Apple Maps. Then disable Wi-Fi and test joystick walk/drive over mobile data. Attempt a new teleport over mobile data only as an **experimental test**; it failed in Locus previously.
9. Keep Locus installed and working until Roam passes these independent tests. Never share device pairing files, Apple ID credentials, or signing certificates in chat or screenshots.

If regeneration is needed, XcodeGen can use the included `project.yml`, but **do not run it unnecessarily**: the supplied `Locus.xcodeproj` is already present and was version-updated with this kit.
