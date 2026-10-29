# Roam v0.8 — Cellular Research Edition

**Status:** Source prepared and Swift syntax checked on Linux. **Not compiled with Xcode and not tested on an iPhone.**

## Goal

Measure why an authenticated iPhone developer tunnel succeeds with Wi-Fi connected but fails on 4G/5G alone. The test deliberately does **not** claim to bypass an Apple security restriction.

## Exactly what changed from the supplied v0.7 source

1. New screen: `Locus/Features/Settings/CellularResearchView.swift`.
2. One navigation link added to `SettingsView.swift` (the earlier v0.7 single-endpoint test remains available).
3. New file registered as a source file in `Locus.xcodeproj/project.pbxproj`; app version **0.8.0**, build **8**.
4. `codemagic.yaml` builds **Release**, unsigned, with an app structure/version verification step.

**Unchanged:** `LocationEngine.swift`, `SpoofSession.swift`, `PairingStore.swift`, `DeviceTunnel.swift`, `LocalDevVPN.swift`, the bundled idevice static library, and all existing location simulation logic.

## Test screen

In the app: **Settings → Cellular research — v0.8 → Wi-Fi / 5G tunnel diagnostics**.

The screen displays:

- Network path indication and IPv4 network interface snapshot, including utun interfaces if present (not a definitive per-socket route).
- Three TCP connect tests to `10.7.0.1`, `127.0.0.1`, and `::1`, on an editable port (default 49152).
- A separate, explicit paired-tunnel/RSD handshake test to `10.7.0.1` or `127.0.0.1` using the existing pairing file, with libidevice's error code and message.
- A local **Copy diagnostic report** button, without pairing-file contents or GPS coordinates. **Review IP/interface data before sharing publicly.**

The paired handshake must be started only while Roam is **not** actively spoofing. It may block while waiting for system networking. The test uses separate adapter/handshake handles and **does not call the location simulation API**.

A TCP "connected" result says only that the port accepted a TCP connection; it is not proof that the authenticated developer protocol works. Conversely, a failed test can reflect iOS interface scoping, VPN route problems, service refusal, or a port mismatch.

## Recommended experiment order

1. Make sure Roam is **not actively spoofing**. Connect LocalDevVPN, leave Wi-Fi **ON** and mobile data **ON**. Record the path and run the three TCP tests.
2. Without ending the VPN, switch Wi-Fi fully **OFF** in iPhone **Settings**. Leave 4G/5G **ON**. Repeat the TCP tests.
3. Back on Wi-Fi, use the paired handshake (VPN endpoint). Record the error/success. With 4G/5G only, repeat it. **Do not change the pairing file.**
4. If both TCP and handshake behave differently, investigate LocalDevVPN's route handling before changing GPS code. If TCP succeeds but handshake fails, look at the authentication/control-channel rejection and port discovery instead.

The screen doesn't implement Bonjour-based dynamic port discovery yet. A manual port field makes a separately discovered port testable without modifying the GPS engine. Dynamic discovery is a proposed next iteration.

## Build / install

The project is structured for the existing Codemagic `roam-ios-unsigned` workflow. On GitHub, push the extracted project to a **private repository** first. Keep the original Roam v0.6 IPA as a backup. Codemagic should output a `Roam.app` artifact; packaging for iloader requires a valid ZIP with `Payload/Roam.app/` as its root, then renaming `.zip` to `.ipa`.

**Critical:** Do not create a ZIP that includes an extra parent directory, and don't assume successful unsigned compilation means successful signing or Apple verification.

## Intellectual property and licensing

- This package derives from the user-supplied Roam/Locus code and retains its existing MIT license and attribution. It does **not** remove third-party copyright or license obligations.
- TCP tests, pairing diagnostics, and VPN route properties are known approaches; this build does **not** represent a verified patentable discovery.
- Before publishing potentially novel technical methods, consult a qualified patent attorney and review prior disclosures, including existing public repository commits. Moving a repository to private **does not undo** past public disclosure.
- Developer-service use remains subject to Apple platform requirements. No universal 4G/5G-only GPS-spoofing capability is claimed.
