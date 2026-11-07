# Roam v0.30 — Build and on-device test plan

## Objective

Preserve the **v0.29 working baseline** while adding opt-in 15- and 30-minute *requested* cruise experiments, elapsed-time UI, and clearer audit evidence. Longer sessions are exploratory, not a bypass of iOS background execution limits.

## Build on Windows 10 with GitHub Desktop and Codemagic

1. Back up the fully working v0.29 project and IPA before modifying the repository. Create branch `roam-v0.30`.
2. Extract `Roam_v0.30_FULL_SOURCE.zip` directly into the existing Roam repository, so `codemagic.yaml`, `project.yml` and `Locus.xcodeproj` are at the repository root. Alternatively apply the incremental patch to a **byte-matching v0.29** source tree.
3. Review the changes, commit (`Roam v0.30: extended cruise trials and health UI`), push to GitHub.
4. In Codemagic, run `roam-ios-unsigned`. The version verification must read `Roam 0.30.0 (30)` and the exported artifact must be `roam-v0.30-unsigned.ipa`.
5. Install using your existing iLoader approach. Point the `Open App` action of **Roam Cold Start**, **Roam Data Off**, and **Roam Data On** to **the actual v0.30 installation** (not an older Roam with the same icon/name).
6. Keep the old v0.29 source and IPA as a rollback option. Do not delete your existing LocalDevVPN or pairing file.

## Regression checks — before any long cruise

- Wi-Fi OFF, mobile data ON, LocalDevVPN disconnected, no active GPS session: launch **Cold Start** from v0.30. Confirm the Shortcut connects VPN, turns cellular OFF, returns to v0.30 and successfully teleports.
- Independently confirm the blue dot in Apple Maps is at the destination. Restore data using the existing Shortcut and re-teleport. Confirm Apple Maps again.
- Run a **20-second** cruise, then a **5-minute** cruise from Command Centre, looking for movement in Apple Maps. Confirm Pause and Stop Movement do not clear the retained GPS session. If any regression occurs, return to v0.29 and send the error message or Codemagic log.

## Extended trial #1 — 15 minutes requested

1. Keep the verified, retained simulation active. Prefer stable battery/charging conditions; do not reset VPN.
2. Open Command Centre → **15-minute cruise** → confirm. Check that progress, requested duration and Cruise Health appear.
3. Switch to Apple Maps to observe whether the dot moves (record approximate observations at minute 1, 5, 10 and 15 if possible). Apple Maps is **the separate, external location check**; Roam's counters alone do not validate movement.
4. After the trial, return to Roam's Command Centre. Record **Observed moving** or **Not moving** and copy the safe summary. Inspect background API counts, gaps, task expirations, observed background time and the end reason.
5. If the task expires, movement stops or Roam is suspended before 15 minutes, report this as **ended early** rather than successful 15-minute movement. Existing retained location should remain until explicitly ended.

## Extended trial #2 — 30 minutes requested

Only attempt this once the 15-minute trial is understood. Follow the same procedure using **30-minute cruise**. Do not assume that because the UI offered a 30-minute window, iOS granted 30 minutes of background execution.

## How to interpret the result

- **Accepted/attempted API calls:** the developer GPS service reported command outcomes; not independent evidence of Apple Maps motion.
- **Requested elapsed time:** elapsed monotonic time until a timer tick reports completion. It does not prove the app ran continuously if iOS paused it.
- **Gaps > 2.5 seconds:** evidence of scheduling or callback interruption; relevant for longer trials.
- **Background-task expiry:** the trial intentionally stops issuing location updates; it does NOT renew tasks automatically.
- **Manual Apple Maps observation:** user-supplied evidence of what was seen on the map. Note whether movement was observed throughout or only part of the trial.
- **Safe summary:** omits coordinates, VPN endpoint IPs, pairing credentials and identifying device information.

## Known platform limits / non-goals

This version does **not** remove the separate LocalDevVPN dependency, obtain new Network Extension permissions, circumvent iOS background restrictions, or guarantee 15/30-minute movement while Roam is backgrounded. The existing Cold Start Shortcut workflow remains intact.

## Build validation scope

Local tests can parse Swift syntax and check project metadata, ZIP integrity and protected-file checksums. Only the user's Codemagic/Xcode build can validate Apple SDK type checking/linking and only actual iPhone testing can verify GPS behaviour.
