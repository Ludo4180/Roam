# Roam v0.27 — VPN-disconnected Cold Start experiment + stability/interface refinement

**Status:** iOS build and device test pending. Base: v0.26 (user-confirmed working on iPhone). All 25 Swift files pass *syntax parsing* with Linux `swiftc -frontend -parse`, but Linux cannot type-check or build the iOS SwiftUI/UIKit app. Use Codemagic's macOS build for real compilation. Preserve v0.26.

## What changed

- A new **Cold Start** card appears above the established One-Tap flow in `Wi-Fi-free startup`.
- The new flow can be explicitly armed even when LocalDevVPN is **disconnected**, provided Wi-Fi is off, cellular network is on, a destination is selected, pairing exists, and no GPS simulation is active. Roam opens a user-created **Roam Cold Start** shortcut. That shortcut requests iOS to connect the *existing LocalDevVPN VPN profile* before turning mobile data off and reopening Roam.
- On return, Roam only attempts its ONE selected-location GPS command after the network monitor reports offline, the previously visible app has been left/returned to, an appropriate VPN-like interface candidate appears, and a bounded read-only TCP test connects to the selected tunnel target (`TunnelConfig.targetIP:targetPort`; usually `10.7.0.1:49152`). A TCP result is **not** proof of paired/RSD connection or Apple Maps positioning, but it prevents unnecessary GPS calls when the VPN route is obviously absent. Retry while armed for at most 90 seconds, with a minimum 4-second gap between probes and 5-second connect timeout.
- Any failure, timeout, cancellation or unavailability of the VPN candidate does **not** disconnect/reset the VPN, delete pairing data, or clear an existing GPS session. Restore data with your existing `Roam Data On` button/Shortcut before retrying.
- App-based, short-lived arm state only (no persisted auto-teleports); one-time pinned coordinate snapshot; opt-in automatic data restoration preserved from v0.26 (OFF by default); manual restore always available. New aggregate Cold Start counters.
- Interface: Quick Start header, experimental Cold Start separated from the proven one-tap flow, long technical manual/diagnostic sections collapsed by default.
- Only the guide and visibility of the already-existing read-only `RoamBoundTCPProbe` helper changed. Pairing engine, GPS engine, LocalDevVPN helper, retention and cruise logic unchanged byte-for-byte.

## Apple ID and VPN constraints

This v0.27 build **does not contain a new VPN extension**, so it requires no new packet-tunnel entitlement and keeps the same unsigned iOS IPA + iLoader process as v0.26. It still relies on the separately installed *original LocalDevVPN app and VPN profile*.

The native Shortcuts **Set VPN** action can request connection of a configured VPN profile. Whether it appears and actually connects **your** LocalDevVPN profile on iOS 27.0.1 needs on-device testing. Roam cannot itself manage a third-party NETunnelProviderManager and cannot guarantee the VPN stays alive while cellular is briefly off. This is **not a LocalDevVPN-free GPS method**, just a possible workaround for *preconnecting LocalDevVPN by hand*.

## Build via GitHub + Codemagic

1. Copy/back up the **working v0.26** source and iLoader-installed IPA.
2. Create branch `roam-v0.27` in your GitHub desktop clone.
3. Extract `Roam_v0.27_FULL_SOURCE.zip` **into your existing Roam repo root**, replacing versioned source/project files. Keep your existing repository `.git` folder and any private signing material intact. Alternatively apply `Roam_v0.27_PATCH_FROM_v0.26.zip` over v0.26 (not earlier versions).
4. Commit and push.
5. Run existing Codemagic workflow `roam-ios-unsigned`.
6. Download artifact `roam-v0.27-unsigned.ipa`; install with your existing iLoader workflow.
7. If Codemagic compilation fails, use `roam-build.log` to locate the first compiler error; do not remove v0.26.

## Before using Cold Start — verify that your v0.26 procedure still works

With Wi-Fi OFF, Cellular ON and LocalDevVPN **already connected**, use your two existing Shortcuts `Roam Data Off` and `Roam Data On`. Verify offline auto-teleport, cellular restore, and Apple Maps mirroring/re-teleport. Update BOTH shortcuts' **Open App → Roam** actions to the v0.27 installation if there are multiple Roam icons.

## Create third Shortcut: **Roam Cold Start**

In iPhone **Shortcuts**, create a new shortcut with exactly that name and these actions, in this order:

1. **Set VPN** — choose **Connect** (or **On**), select the existing **LocalDevVPN** VPN profile **using the VPN picker**. Do not type the VPN name as plain text. If LocalDevVPN is missing from the picker, this method is not available as written.
2. **Wait** — 5 seconds, to allow the VPN to reach Connected. This delay may be insufficient on some devices; you can increase it if necessary.
3. **Set Cellular Data** — **Off**.
4. **Open App** — **Roam v0.27** (be careful if two versions are listed).

First test the VPN action *separately* from the full sequence. With Wi-Fi OFF and Cellular ON, set LocalDevVPN **Disconnected** in iOS Settings (do not delete the VPN configuration); run a test shortcut containing only **Set VPN → Connect → LocalDevVPN**. Confirm iOS Settings → VPN shows **Connected**. If it fails or the profile cannot be selected, use the old workflow: open the original LocalDevVPN and connect it manually, then use `Roam Data Off`.

## First complete Cold Start test

1. Ensure **no active GPS simulation** in Roam. Stop only when ready; do not end a retained working session merely to conduct this test.
2. Restore cellular ON and Wi-Fi OFF.
3. Disconnect LocalDevVPN from iOS Settings (do not delete/uninstall).
4. Open **Roam v0.27**, select a destination, open **Wi-Fi-free startup**.
5. Tap **Cold Start · Connect VPN & Teleport**. It runs **Roam Cold Start** and returns to Roam when finished.
6. Roam checks for an *offline* network path, a matching VPN-like interface and successful local TCP reachability. If these occur within 90 seconds, it will make *one* GPS teleport attempt. Otherwise it will time out and require you to recover manually.
7. Verify the location in **Apple Maps**. API acceptance by itself does not confirm Apple Maps moved.
8. Use **Restore Mobile Data** (or optionally enable auto-restore *before* arming the test). Wi-Fi remains OFF. Verify cellular data works and re-teleport to a second destination.
9. Repeat 2–3 times only after initial success. Inspect **Diagnostics, statistics & manual steps** for separate Cold Start attempts/API accepts/failures.

## Failure recovery — protect your working setup

If Shortcuts opens without the right VPN profile, if no `utun` candidate appears, or if the TCP route still refuses connections:

- Select **Restore Mobile Data**. If that Shortcut is unavailable, turn Mobile Data ON manually in iPhone Settings.
- Open the original LocalDevVPN and connect it manually. Confirm iOS Settings shows Connected.
- Fall back to the *already verified* v0.26 One-Tap startup (VPN connected → Data Off Shortcut → one accepted GPS command → Data On Shortcut).
- Do not reset the pairing file, uninstall LocalDevVPN, delete its VPN profile, change the developer port or touch the protected location engine.
- Share the **on-screen feedback string**, which distinguishes *no VPN candidate*, *local peer refused/timeout*, and *GPS API failure*.

## What would count as a breakthrough?

A full run starting with **VPN genuinely Disconnected**, Wi-Fi OFF and Cellular ON, where Shortcuts connects LocalDevVPN, switches cellular off, Roam accepts the new GPS command, Apple Maps mirrors, and a mobile-data restoration permits re-teleport. That would remove the *manual VPN preconnection step*. It would **not** mean Roam works independently without LocalDevVPN installed or that iOS permits pairing with cellular continuously ON.
