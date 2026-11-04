# Roam v0.15 — app lifecycle and cruise resume diagnostics

Built on the tested v0.14.1 source. This is a diagnostic **foreground recovery** build, **not** a solution for uninterrupted background location simulation.

## Changes
- Logs active / inactive / background scene transitions and whether a retained simulation handle was present.
- On background entry, explicitly pauses cruise without clearing the simulated GPS position or developer session.
- Records the remaining *active* cruise duration.
- On return to foreground, resumes the remaining cruise duration automatically **only if** the prior session and pairing file remain available. It does not attempt a new developer handshake on mobile data.
- Never calculates a large jump for time spent in the background.
- Does not auto-resume joystick movement, which requires an actively held control.
- Lifecycle events and remaining duration appear in Movement Diagnostics and exported text.

## Build on Codemagic
1. Back up the working v0.14.1 source and IPA.
2. Create a `roam-v0.15` GitHub branch from the latest project.
3. Replace repository contents with this full-source ZIP, or apply the patch ZIP to the exact v0.14.1 source.
4. Commit and push; run the existing `roam-ios-unsigned` Codemagic workflow.
5. Download the unsigned IPA artifact and install with your established signing/iLoader workflow.

## Controlled test
1. Wi-Fi ON + LocalDevVPN connected: start a successful teleport to establish the developer session.
2. Wi-Fi OFF + mobile data ON: check a retained re-teleport works.
3. In Roam, start `Move north for 20s` at Walk speed.
4. After ~5s, switch to Apple Maps for 10-15s; **no background movement is expected**.
5. Return to Roam: check that cruise resumes for the unused remaining time.
6. Wait until cruise completes, then check the final Apple Maps location.
7. Open Movement Diagnostics and copy lifecycle events and accepted/failed GPS update counts.

## Limitations
- A normal third-party app cannot assume indefinite iOS background execution. This build pauses rather than attempting unsupported continual background developer-service operations.
- No code signing or actual iOS SDK compile has been run here; Swift syntax parsing was checked locally. Codemagic will establish whether the project compiles and the iPhone will establish whether recovery works.
- Developer service acceptance and Core Location callbacks are not proof of movement inside Apple Maps.
- Do not share your pairing file or signing credentials.
