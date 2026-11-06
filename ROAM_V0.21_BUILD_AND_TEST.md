# Roam v0.21 — Pinned Controls and MPH

## UI fix

The expanded controls in v0.20 used a single ScrollView containing the complete card. On scroll, this moved the **card's own top and title** out of sight, leaving a hard clipped edge over the map (as shown in the user screenshots).

v0.21 places the expanded controls within a single rounded, clipped `roamSurface` container. A dedicated **non-scrolling header** displays Movement Mode, Choose your pace, the selected speed, and Minimise. A separator divides the header from the **internal 350-point scroll region**, which is the only part that moves. Scrolling can no longer move the card's own rounded top offscreen.

The screen continues to offer the compact controls after teleport; **Minimise does not end or reconnect the simulated GPS session**.

## Speed units

Only the **display** changes from km/h to mph. The speed source remains `TravelMode.baseSpeed` in metres per second, multiplied by approximately `2.2369362921` for the label. The four approximate display values are:

| Travel mode | Screen preset |
| --- | --- |
| Walk | 3 mph |
| Run | 7 mph |
| Cycle | 15 mph |
| Drive | 30 mph |

There are no changes to GPS movement distances, timers, pairing, network routing or background-cruise execution.

## Build on Windows with GitHub Desktop + Codemagic

1. **Back up** tested Roam v0.20 source and its working IPA.
2. Create a GitHub Desktop branch `roam-v0.21` from v0.20.
3. Extract **Roam_v0.21_FULL_SOURCE.zip** to the repository root, replacing the corresponding files. Alternatively, apply **Roam_v0.21_PATCH_FROM_v0.20.zip** on exactly v0.20 (not older versions).
4. Commit and push to GitHub.
5. Select branch `roam-v0.21`, workflow **`roam-ios-unsigned`** in Codemagic and build.
6. Confirm Step 4 reports **Roam 0.21.0 (21)**. Expected artifact: **`roam-v0.21-unsigned.ipa`**.
7. Sign/install with the existing iLoader process. Keep LocalDevVPN installed.

## Test on iPhone 17 Pro

1. With the established, working Wi-Fi-assisted developer session, teleport; ensure the compact bar appears automatically.
2. Tap **Expand**. Verify that the **rounded top of the control panel remains visible**, with `MOVEMENT MODE`, `Choose your pace`, selected `mph` preset, and `Minimise` visible.
3. Scroll down through `20s`, `30s`, `60s`, `90s`, `2m`, `5m`, diagnostics, and the Stop/Pause controls. The panel should scroll **only below the fixed header**. Scroll back up and check that the panel top is still intact.
4. Switch Walk, Run, Cycle, Drive and verify **3 / 7 / 15 / 30 mph** labels; movement speed itself should be unchanged.
5. Tap **Minimise**, select a different location on the map, and **Re-teleport**. Check Apple Maps independently.
6. Optional regression: try the successful **20s experimental background cruise** on a retained 4G/5G session and confirm diagnostics and Apple Maps behaviour. Do not begin with a 5-minute test.

## Validation status and limitations

- Local Swift syntax parsing (all source files), YAML parsing, archive integrity, and source diffs have been checked.
- The developer-service and simulation logic is identical to v0.20, apart from two human-readable diagnostic version labels.
- The full Xcode build, actual SwiftUI layout and on-device GPS tests still require Codemagic and the iPhone.
- A Wi-Fi-to-cellular retained session has been tested previously. Initial developer pairing entirely over cellular remains unresolved.
- Background execution is not guaranteed by iOS even when previous finite tests were successful.
- Do not upload sensitive pairing files, credentials or signing keys into a public repo.
