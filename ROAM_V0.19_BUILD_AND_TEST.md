# Roam v0.19 — Long-duration background reliability trials

## Proven baseline and purpose

**v0.18 user test (5 November 2026):** Apple Maps showed the blue location dot moving during 20, 30 and 60-second background trials on cellular after a Wi-Fi-established developer session. The 60-second trial log reported 63/63 accepted background API updates, no failures, zero gaps >2.5 seconds, maximum gap 0.80 seconds and no task expirations. This establishes a **short-duration test result**, not guaranteed future performance, independent 5G-only pairing, or indefinite iOS background execution.

**v0.19** keeps the existing 20/30/60-second commands and all pairing/teleport/joystick code. It adds separate **90-second, 120-second (2 minute), and 300-second (5 minute)** user-initiated trials. These are *requested scheduling windows* only. Each trial requests **one finite** `UIApplication.beginBackgroundTask` and never chains or renews tasks to force a longer run.

## Additional diagnostic and safety behaviour

- Stops and holds the last API-accepted simulated coordinate when the iOS expiration handler runs, and ends the background-task identifier.
- While backgrounded and able to run, samples `UIApplication.backgroundTimeRemaining`; stops safely when the reported allowance is 5 seconds or less. The allowance is not guaranteed and iOS may suspend or terminate even earlier.
- Captures actual monotonic elapsed test duration, measured intervals in background state, minimum sampled background allowance (if available), longest observed command gap, number of gaps >2.5 seconds, accepted/failed API requests, requested distance, task expirations and safety stops.
- Retains up to eight short trial summaries **in memory** for comparisons. These summaries disappear when the app restarts; export the diagnostic report before restarting. No pairing file or credentials are included in exported logs. The report *does include simulated coordinates and timestamps*.
- If interrupted, the experimental trial does **not** automatically resume or open a fresh developer pairing over cellular. Standard foreground cruise and joystick are unchanged.

## Windows -> Codemagic -> iLoader

1. Back up the tested v0.18 repository branch, source and IPA first.
2. In GitHub Desktop create and publish branch **`roam-v0.19`**, preferably based on v0.18.
3. Extract the **FULL SOURCE** ZIP into the Git repository root without adding a wrapper directory. Or apply the **PATCH** on top of v0.18 (not v0.17).
4. Commit and push. In Codemagic choose `roam-v0.19`, workflow `roam-ios-unsigned`.
5. Step **Verify output version and app structure** should report **Roam 0.19.0 (19)**. Expected unsigned artifact is **`roam-v0.19-unsigned.ipa`**.
6. Download and install using your existing iLoader method. Do not remove LocalDevVPN or the working backup.

## Test sequence (one experiment at a time)

1. With phone stationary, first confirm initial teleport over Wi-Fi, then disable Wi-Fi **in Settings**, leave 4G/5G on, retain LocalDevVPN and confirm cellular re-teleportation. Do not force-close Roam or restart pairing during handover.
2. In Roam, select Drive and run the **20s baseline**, switch to Apple Maps after ~3s, watch the blue dot, then return to Roam and export Movement Diagnostics. If the baseline regresses, stop testing and retain v0.18.
3. Repeat with 60s to establish a comparison. Then run **90s**, **2m**, and only after those, **5m** separately. Keep the iPhone stationary and charging if practical; avoid low-power mode changes during a test. Do not repeatedly launch background tasks to circumvent an iOS expiration.
4. For each run check planned duration vs elapsed duration, measured background time, last command time, background attempts/accepted/failed, longest gap and gaps >2.5s, task expirations, budget-safety stop, end reason and the corresponding visible movement in Apple Maps.
5. Record whether the blue dot moved throughout the run, stopped early or jumped to the end. The API acknowledgment **does not independently prove** Apple Maps moved during every second. If the trial stops early, treat that as useful evidence of iOS limits; do not claim the entire duration was successful.

## Limitations / validation

- v0.19 is a research build and may not run for 2 or 5 minutes in the background. Apple can suspend the app, revoke the finite task, or terminate its process; `beginBackgroundTask` is not a continuous-execution entitlement.
- The project is locally checked for **Swift syntax**, YAML structure, archive integrity and version agreement only. **iOS SDK compilation, real background-time limits and device operation require Codemagic and iPhone testing.**
- This does not enable initial RPPairing/RSD over cellular without the Wi-Fi-established session.
- Keep any private pairing documents, signing certificates and API secrets outside Git and ZIPs.
