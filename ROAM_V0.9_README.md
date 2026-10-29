# Roam v0.9 — cellular failure isolation (experimental source)

Based on v0.8 research source, not a verified iPhone build. v0.6 remains untouched.

## Changes
- Disable automatic 8-second resends and 12-second reconnect checks by default, to prevent uncontrolled commands during network transition experiments.
- On failure to update an existing simulation, retain the existing handle rather than automatically tearing it down and attempting to reconnect. This is **not** a guarantee that iOS keeps the override; it may leave a stale handle until the user explicitly stops/restarts.
- Stop joystick and route commands after a failed update to avoid repeated failures.
- Add developer port override in Settings (default 49152). **Manual** configuration only; no automatic Bonjour discovery is claimed.
- Show last engine stage and failure in Settings. Stage labels are high-level; low-level socket error strings are not exposed by the current FFI wrapper.

## Build / test
1. Back up your current repository. Unpack into a **separate branch or directory**. Do not replace your working installed v0.6.
2. Build using existing Codemagic `roam-ios-unsigned` workflow. This package contains Vendor/idevice/libidevice_ffi.a.
3. Before installing, check that your signing/installation process will not overwrite v0.6; use a separate bundle ID or back up the old IPA and pairing file.
4. Baseline: Wi-Fi OFF, cellular OFF, LocalDevVPN connected: teleport and verify in Apple Maps.
5. Turn cellular ON, wait two minutes, do not send commands, then attempt one joystick movement. Check Apple Maps and Settings > Last engine stage/failure.
6. Do not share pairing files, certificates, private keys or full logs containing them.

## Known limitations
- No automatic port discovery, network-route repair, or proven 4G/5G control.
- No local iOS toolchain here; compile/runtime behavior requires Codemagic/iPhone verification.
- UI diagnostic labels update when Settings is reopened, not continuously.
- Keeping a stale handle can require app restart to re-establish a session; this is a diagnostic trade-off.
