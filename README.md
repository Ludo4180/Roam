# Roam v0.24 — Wi-Fi-free startup workflow

Built from the user-tested v0.23 source. GPS simulation, original LocalDevVPN compatibility, joystick, GPS diagnostics, 20/30/60/90/120/300-second experimental background movement and mph interface remain unchanged.

**New:** an opt-in Wi-Fi-free startup guide accessible from the map controls and Settings. The guide shows the iOS network path, pairing-file presence, a *candidate* VPN interface (not authenticated), the retained developer session handle, engine result, and a manual Start / Re-teleport button for the selected map pin. It provides recovery guidance and optional instructions for creating two native iOS Shortcuts.

## User-confirmed procedure

1. With cellular data available, connect the original LocalDevVPN. Check Settings > VPN.
2. In Settings, turn **Wi-Fi OFF** and temporarily turn **Mobile Data OFF**, leaving the VPN connected.
3. Return to Roam, choose a destination and **Teleport** to establish a new simulated GPS session while offline.
4. Turn **Mobile Data ON** again (keep Wi-Fi OFF). Check Apple Maps; re-teleport should work over cellular. The user also confirmed re-teleporting while data stayed OFF.

This workflow was reproduced on the user's iPhone, but it is **not** proof of a fresh VPN establishment while cellular remains ON. A VPN-interface candidate or retained GPS handle is not independent proof Apple Maps changed: verify externally.

The app **does not** toggle Wi-Fi/mobile data itself, change VPN settings or reset a retained GPS session. If Shortcuts is available, users may manually create `Set Cellular Data: Off` and `Set Cellular Data: On` actions in separate Shortcuts. No Shortcut files are supplied or auto-run.

The project builds with `roam-ios-unsigned` in Codemagic; `roam-v0.24-unsigned.ipa` is produced after the iOS build. See `ROAM_V0.24_BUILD_AND_TEST.md`.

**Important:** Keep v0.23's working source and IPA backed up. Preserve private RPPairing credentials and do not publish them.

## Previous diagnostics retained

- v0.23 cellular route audit captures ordinary and bound TCP tests, path observations and independent Wi-Fi/cellular baselines under Cellular Research.
- Earlier versions' 20s through 300s background cruise experiments remain in the original session engine, untouched by v0.24.
