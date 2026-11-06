# Roam v0.21 — Clean Scrolling Controls + MPH

A focused interface update based directly on **Roam v0.20**, preserving its working automatic minimisation, compact Re-teleport bar, retained developer session, joystick, and 20/30/60/90/120/300-second experimental background cruise tests.

## What's different

- **Pinned movement header:** `MOVEMENT MODE`, `Choose your pace`, speed, and `Minimise` stay visible at the top of the expanded control panel.
- **Contained scrolling:** only the movement buttons and diagnostics shortcuts scroll inside the rounded panel. The card itself no longer scrolls upward and appears cut off at the top.
- **MPH rather than km/h:** walking, running, cycling, and driving presets display miles per hour (3, 7, 15, and 30 mph respectively). The underlying movement speeds remain **unchanged** in metres per second.
- **Previous minimising preserved:** teleport automatically collapses the expanded controls; `Expand`, waveform diagnostics, and `Re-teleport` remain on the compact bar. Minimise never stops the GPS session.

**Version:** `0.21.0 (21)`  
**Codemagic workflow:** `roam-ios-unsigned`  
**Expected artifact:** `roam-v0.21-unsigned.ipa`

Build instructions and on-device checks: [ROAM_V0.21_BUILD_AND_TEST.md](ROAM_V0.21_BUILD_AND_TEST.md).

Local Swift syntax checks cannot replace the Apple iOS SDK compile and device testing. Keep the working v0.20 source and IPA backed up. The cellular-only initial developer connection remains unresolved.
