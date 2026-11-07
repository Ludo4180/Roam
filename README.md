# Roam v0.29 — Command Centre & resilient Cold Start

Roam v0.29 builds on the **user-tested v0.28**, including the verified Wi-Fi-free Cold Start, Apple Maps mirroring, re-teleportation with cellular OFF and restored ON, and a five-minute observed northbound movement trial.

## New in v0.29

- **Roam Command Centre** on the map: one consolidated panel for Cold Start, Teleport/Re-teleport, 20-second or five-minute background cruise, Pause, End GPS Session and Recovery.
- A compact-controls Command Centre button and a clearly labelled shortcut in the expanded movement controls.
- Safer connection language: an active GPS session remains shown as active even when the VPN interface candidate is temporarily absent. VPN interface detection alone does **not** prove authentication.
- A privacy-conscious, locally generated Command Centre summary with no map coordinates or pairing material.
- Separate research notes on **removing the installed LocalDevVPN dependency**. No unsupported VPN extension or unverified connection bypass is bundled.
- Updated version metadata and Codemagic verification to **0.29.0 (29)** to avoid the v0.27 build-number mismatch.

**Preserved exactly:** Every source file in `Locus/Engine/`, the LocalDevVPN adapter, the original pairing and location simulation interfaces, and existing experimental background movement. The original Cold Start and Shortcuts state machine has no behavioural changes. No new entitlements.

This ZIP contains **source code, not a signed or working IPA**. Codemagic compilation and iPhone testing are still required. Full instructions are in [ROAM_V0.29_BUILD_AND_TEST.md](ROAM_V0.29_BUILD_AND_TEST.md). Review [connection-independence research](ROAM_V0.29_CONNECTION_INDEPENDENCE_RESEARCH.md) before attempting changes to the VPN stack.

## Confirmed limitations

- The installed **LocalDevVPN is still required** for the current successful on-device developer pairing path. The `Roam Cold Start` iOS Shortcut connects that profile automatically; it does **not** remove the dependency.
- The iPhone must already have the working pairing configuration and the user's three Shortcuts correctly targeting the latest app installation.
- A local GPS API acknowledgement is not proof of system-wide movement. Continue verifying with Apple Maps.
- Background cruise can be stopped or suspended by iOS before its planned duration.

Preserve a working copy of **v0.28** before upgrading.
