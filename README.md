# Roam v0.22 — Fresh 4G/5G Connection Diagnostic

Built from the user-confirmed v0.21 source. This update keeps existing location simulation and background-cruise code intact, and adds a read-only paired-handshake comparison plus opt-in Remote Pairing port discovery to Settings.

- `ROAM_V0.22_BUILD_AND_TEST.md`: installation, controlled comparison procedure, and interpretations.
- `codemagic.yaml`: `roam-ios-unsigned` build, version check for `0.22.0 (22)`, unsigned IPA name `roam-v0.22-unsigned.ipa`.
- Location engine and VPN/provider interfaces are **not** modified. Selecting a different port only takes effect on a **new** developer session and must be deliberate.

**Important:** A successful TCP connection, visible VPN icon or accepted port discovery is not a successful developer tunnel. LocalDevVPN developers have reported that fresh cellular-only routing is restricted on current iOS versions. This is an investigative build, not a promise that Wi-Fi-free startup is solved.

**Do not publish device pairing files**; they are private credentials.

## Roam v0.23 — Read-only cellular route comparison

The cellular research screen includes a new **v0.23 CELLULAR ROUTE COMPARISON** section. Capture a Wi-Fi baseline, turn Wi-Fi off in iOS Settings, capture a cellular baseline, then copy the report. This compares ordinary TCP, candidate utun-bound TCP, radio-interface-bound TCP, loopback, and Network.framework path observations without modifying GPS or VPN settings. See `ROAM_V0.23_BUILD_AND_TEST.md`.
