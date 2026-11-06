# Roam v0.25 — one-tap Shortcuts-assisted Wi-Fi-free startup

Built from the user-tested v0.24 source. GPS simulation, original LocalDevVPN compatibility, joystick, GPS diagnostics, 20/30/60/90/120/300-second experimental background movement and mph interface remain unchanged.

**Retained from v0.24:** an opt-in Wi-Fi-free startup guide accessible from the map controls and Settings. The guide shows the iOS network path, pairing-file presence, a *candidate* VPN interface (not authenticated), the retained developer session handle, engine result, and a manual Start / Re-teleport button for the selected map pin. It provides recovery guidance and optional instructions for creating two native iOS Shortcuts.

## User-confirmed procedure

1. With cellular data available, connect the original LocalDevVPN. Check Settings > VPN.
2. In Settings, turn **Wi-Fi OFF** and temporarily turn **Mobile Data OFF**, leaving the VPN connected.
3. Return to Roam, choose a destination and **Teleport** to establish a new simulated GPS session while offline.
4. Turn **Mobile Data ON** again (keep Wi-Fi OFF). Check Apple Maps; re-teleport should work over cellular. The user also confirmed re-teleporting while data stayed OFF.

This workflow was reproduced on the user's iPhone, but it is **not** proof of a fresh VPN establishment while cellular remains ON. A VPN-interface candidate or retained GPS handle is not independent proof Apple Maps changed: verify externally.

**New in v0.25:** optional native Shortcuts-assisted startup. Create two user-owned Shortcuts named **Roam Data Off** (Set Cellular Data to Off, then Open App → Roam) and **Roam Data On** (Set Cellular Data to On, then Open App → Roam). The in-app button launches the first Shortcuts URL only after the user explicitly arms a one-shot teleport and confirms VPN connected. On returning to foreground, Roam sends one teleport to the preselected pin **only if the network path reports offline and the 90-second window is still open**. An obvious manual button runs the second Shortcut to restore data. Shortcuts must be installed and set up by the user; Roam does not know whether the Shortcut actually toggled data, and the returned result must be confirmed in Apple Maps.

The app **does not** toggle Wi-Fi/mobile data itself, change VPN settings, reset a retained GPS session, or create Shortcuts automatically. An offline NWPath result is not conclusive proof of either radio's setting. If any step fails, restore mobile data via iPhone Settings and use v0.24's manual guide.

The project builds with `roam-ios-unsigned` in Codemagic; `roam-v0.25-unsigned.ipa` is produced after the iOS build. See `ROAM_V0.25_BUILD_AND_TEST.md`.

**Important:** Keep the working v0.24 source and IPA backed up. Preserve private RPPairing credentials and do not publish them.

## Previous diagnostics retained

- v0.23 cellular route audit captures ordinary and bound TCP tests, path observations and independent Wi-Fi/cellular baselines under Cellular Research.
- Earlier versions' 20s through 300s background cruise experiments remain in the original session engine, untouched by v0.25.
