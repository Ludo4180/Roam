# Roam v0.18 — Build & Test Guide

## Purpose

Baseline v0.17: user observed live simulated movement in Apple Maps over 4G while Roam was backgrounded during a 20-second cruise after Wi-Fi initialisation, and reproduced it. v0.18 preserves this path and adds **30-second** and **60-second** experiments. These are **requested trial lengths, not guaranteed background CPU time**.

## Changes

- Three separately selected **20s / 30s / 60s** experimental cruise buttons. The original **Move north for 20s** standard cruise remains separate and intentionally pauses in the background.
- Every experiment requests **one** finite `UIApplication.beginBackgroundTask`, before entering the background, and ends it on completion, manual stop, failure or UIKit expiration. Expiration **stops** the experimental cruise and does **not** silently restart it.
- Diagnostic fields: selected trial duration, elapsed scheduling time, reason for ending, background API attempts/acceptances/failures, distance requested and acknowledged, number of command-timer gaps > 2.5 seconds, longest observed gap and background-task expiration count. Gaps and missing calls indicate interruptions; no catch-up GPS jump is sent.
- Existing developer pairing, tunnel IPs, working 4G retained session, GPS engine, and joystick implementation are not redesigned.

## Windows → Codemagic build

1. Keep the **successful v0.17 source, IPA and Codemagic build** as a separate backup.
2. In GitHub Desktop create the `roam-v0.18` branch from your latest working branch.
3. Extract the **FULL SOURCE** archive into the repository root, replacing existing project files, **without nesting an extra folder**. Alternatively apply the PATCH from the v0.17 source root.
4. Commit, push, then choose the branch and run workflow `roam-ios-unsigned` in Codemagic.
5. Ensure **Step 4 Verify output version** displays `0.18.0 (18)` and Step 5 packages `roam-v0.18-unsigned.ipa`.
6. Download the IPA, sign/install with your existing iLoader method, and keep LocalDevVPN installed.

## iPhone test (controlled and incremental)

1. Confirm Wi-Fi-established initial teleport still works, then turn **Wi-Fi OFF in Settings**, leave 4G/5G ON and LocalDevVPN connected, and confirm **re-teleport** is working.
2. Choose a safe, stationary test setup and **Drive** mode. Use the **20s** experimental trial first to reproduce the v0.17 result. Start, wait about 3s, switch to Apple Maps; watch for live blue-dot movement.
3. Return to Roam and inspect **Movement Diagnostics → Extended background cruise (v0.18)**. Note planned duration, elapsed, background API attempts/accepted/failed, gaps, expirations, and end reason.
4. After the 20s baseline, repeat with **30s**, then **60s**, without altering other settings. For 60s, expect that iOS **may terminate background execution early**. Do not repeatedly restart a trial to evade iOS's background limits.
5. Verify Apple Maps visually; accepted simulation API calls alone do not independently establish system-wide movement. Consider repeating each trial before assessing reliability.

## Interpretation

- `Scheduling window elapsed` with many accepted commands and no large gaps suggests sustained command execution for the requested period; visually verify in Apple Maps.
- `iOS background task expired` or a large scheduling gap means the length was **not fully demonstrated**; the session is kept, movement stops, and the experiment is recorded as interrupted.
- Zero background attempts means the app did not execute location commands while in background, regardless of its foreground work.
- A retained developer session established with Wi-Fi still **does not prove** a 4G-only initial developer connection.

## Validation and privacy

The source is locally syntax-parsed but iOS SDK **typechecking, signing and device testing require Codemagic/iPhone**. Diagnostic exports include simulated coordinates and lifecycle timestamps; review before sharing. Keep pairing files and Apple credentials out of ZIPs and screenshots.
