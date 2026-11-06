# Roam v0.20 — Minimisable Controls and Diagnostics

## What this release changes

This is a **map usability update** built directly on the working **v0.19** source, not a redesign of the GPS simulation or developer tunnel. v0.19's experimental 20/30/60/90/120/300-second background cruise implementation remains intact.

- **Automatic minimisation after successful initial teleport:** the large movement-control panel collapses into a narrow bar. The map is available for tapping another location.
- **Compact bar:** `Expand` opens the full movement controls; the waveform icon opens GPS Movement Diagnostics; `Re-teleport` updates the retained session to the currently selected map pin. When no session is active, it is labelled `Teleport`.
- **Manual Minimise:** in the expanded panel, tap **Minimise** to return to the compact bar without ending GPS simulation.
- **Scrollable expanded panel:** its height is limited, so it does not occupy the whole screen even when expanded. Scroll the panel to reach speed, joystick, background cruise buttons and End Simulation.
- **Minimisable diagnostics:** GPS Movement Diagnostics opens as a medium-height sheet; drag upwards for full detail, or tap **Minimise** to dismiss it and collapse the controls. The diagnostics data stays in memory and is available when reopened.
- **Cruise safety:** while the compact bar is displayed during an active cruise, **Stop movement** remains visible. This intentionally stops movement, not the simulated GPS session.

**Important:** The minimisation controls change only what is visible. They never call `session.stop()`, clear GPS, disconnect LocalDevVPN, or open a new developer connection. Normal teleportation still invokes the same `session.teleport(to:pairing:)` method used by v0.19.

## Build on Windows with GitHub Desktop + Codemagic

1. Back up your tested **v0.19 source and IPA**. In GitHub Desktop, create a branch named **`roam-v0.20`** from v0.19.
2. Extract **Roam_v0.20_FULL_SOURCE.zip** into the repository root, without adding an extra parent folder. Alternatively, apply **Roam_v0.20_PATCH_FROM_v0.19.zip** to the matching v0.19 repository.
3. Commit and push the changes.
4. In Codemagic, select branch `roam-v0.20` and workflow `roam-ios-unsigned`.
5. The **Verify output version and app structure** step should read **Roam 0.20.0 (20)**. The expected artifact is **`roam-v0.20-unsigned.ipa`**.
6. Download and install the IPA with your normal signing/iLoader procedure. Keep LocalDevVPN and the backup of the working build.

## On-iPhone tests

### A — Verify map and re-teleport

1. With Wi-Fi enabled and LocalDevVPN connected, choose a point (for example, Edinburgh) and tap **Teleport**.
2. When the GPS session becomes active, confirm that the bottom controls automatically **minimise** to a small bar.
3. Without stopping the simulation, tap a **different point on the exposed map** or search for another destination.
4. Tap **Re-teleport** directly from the compact bar. Check Apple Maps independently to confirm it shows the new simulated location.
5. Switch Wi-Fi fully off in iPhone Settings while retaining the established session and cellular data; verify the same re-teleport procedure on 4G/5G.

### B — Expand and minimise

1. Tap **Expand** on the compact bar; the large controls panel should appear, but not fill the screen.
2. Scroll inside the panel to reach movement-speed presets, joystick, background cruise buttons and diagnostics.
3. Tap **Minimise** on the panel. The map should become easy to select again, and the simulated GPS location should **not** clear.
4. On the compact bar, tap the **waveform** icon. Diagnostics should open at medium height; drag it taller if required.
5. Tap **Minimise** in the diagnostics sheet. The sheet should close and leave the compact map bar visible. Reopen diagnostics and confirm prior movement counters remain.

### C — Short regression check

Run the **20-second experimental background cruise** using the same established Wi-Fi-to-cellular session as v0.19. Confirm Apple Maps movement and review the diagnostic result. Do not repeat the five-minute test until v0.20's map interaction is confirmed stable.

## Validation and limitations

- Local validation: Swift **syntax parsing**, consistency of Codemagic/Xcode version declarations, YAML parsing, archive integrity and preservation of the movement/tunnel implementation against v0.19.
- **Not yet validated:** full Apple iOS SDK compilation, actual SwiftUI layout on-device, or GPS behaviour. Codemagic and iPhone testing remain necessary.
- The initial developer pairing over **cellular alone** remains unresolved; a previously Wi-Fi-established session is still used for the successful 4G/5G handover experiments.
- No background-execution technique is guaranteed to be indefinitely reliable under iOS. The 300-second trial is an observed test result, not an operating-system guarantee.
- Never upload private pairing files, Apple developer credentials or signing keys to the repository or these packages.
