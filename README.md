# Roam v0.30 — Extended Cruise & Session Health

Roam v0.30 builds on the **iPhone-tested v0.29** Command Centre, assisted Cold Start, Apple Maps mirroring, repeated 5-minute northbound cruises, and re-teleportation.

## What changed in v0.30

- **15-minute and 30-minute northbound cruise experiments** in Command Centre. Each requires explicit confirmation. These are *requested windows*, not promised background runtime: iOS can suspend the application or end its single finite background task before the requested duration.
- **Live requested-time progress** in Command Centre, labelled as a timer estimate—not verified GPS movement.
- **Cruise Health card**: background API attempts/acceptances/failures, longest scheduling gap, gaps above 2.5 seconds, task expiration and background budget observations. All are internal diagnostics, not proof of Apple Maps movement.
- **Manual external observation**: note whether you saw Apple Maps moving, then copy a privacy-conscious Command Centre summary without coordinates, endpoints or pairing credentials. The observation is saved *only while the Command Centre view is open*.
- **More accurate recovery instructions**: a cruise requires an active *retained GPS simulation*; Wi-Fi is no longer prescribed if the proven Shortcut-assisted Cold Start has already established the connection.
- **Codemagic / Xcode version** set to `0.30.0 (30)`, output `roam-v0.30-unsigned.ipa`.

## What was deliberately left alone

The pairing and GPS communication implementation in `Locus/Engine/LocationEngine.swift`, `Locus/Engine/DeviceTunnel.swift`, `Locus/Engine/PairingStore.swift`, `Locus/Engine/PairOnDeviceService.swift`, and `Locus/Support/LocalDevVPN.swift` is unchanged from v0.29. Background-cruise update logic and the existing single background task are retained; only the allowed requested durations and UI progress metadata were extended in `SpoofSession.swift`. No automatic task renewal, entitlement trick, or external VPN replacement was added.

## Getting started

See [ROAM_V0.30_BUILD_AND_TEST.md](ROAM_V0.30_BUILD_AND_TEST.md). Back up v0.29 first. This is **source code**, not a signed IPA. It has not been compiled on Xcode or tested on the user's phone.

## Critical limitation

An iOS foreground timer can run for a requested 15/30 minutes, but background execution has system limits. An API acceptance is not independent evidence of continuous system-wide location; verify live movement through Apple Maps. The application currently relies on the separate LocalDevVPN app and iPhone Shortcuts for Cold Start.
