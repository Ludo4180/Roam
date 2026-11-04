# Roam v0.16 — app handover measurement

## Purpose
This is a **diagnostic** continuation of working v0.15. It is not a claim that iOS allows continuous developer location-simulation commands in the background. It deliberately pauses movement upon entering background, retains the last simulated coordinate, and resumes the unfinished foreground cruise when Roam is reopened.

## New in v0.16
- Shows the number of background transitions and the measured duration of the latest period away from Roam.
- Logs the timestamp of the latest API-accepted location update, and how many times a cruise recovered upon return.
- Shows a clearly marked *hypothetical* distance that would have been travelled while Roam was not active. **This distance is never sent as a GPS update.**
- Keeps the v0.15 remaining-duration recovery strategy, 20-second north test, joystick and 4G retained-session re-teleport implementation.
- Diagnostic report includes the new handover fields; the exported report includes coordinates, so review it before sharing.

## Codemagic build
1. Keep a backup of working v0.15 source and IPA.
2. Create a new `roam-v0.16` branch in GitHub Desktop, based on your existing v0.15 source.
3. Either replace repository contents with the full-source package or apply the patch to *exactly* v0.15; do not stack both.
4. Commit and publish branch; run existing `roam-ios-unsigned` workflow in Codemagic.
5. Install compiled IPA using your established signing/iLoader procedure. Do not delete LocalDevVPN.

## Test sequence
1. With Wi-Fi ON and LocalDevVPN connected, establish a successful initial teleport.
2. Turn Wi-Fi OFF (mobile data ON) and confirm retained-session re-teleport still works in Apple Maps.
3. Start the 20-second northward cruise at Walk speed.
4. After about 5 seconds, switch to Apple Maps for around 10 seconds. The blue dot is expected to remain at the latest position; **no background update is expected**.
5. Return to Roam: verify the remaining cruise resumes, then open Movement diagnostics and note **Background entries**, **Last time away**, **Foreground recoveries**, **Last accepted command**, and **Hypothetical distance while away**.
6. After the cruise finishes, compare the final coordinate against Apple Maps. Copy diagnostic report if results differ.

## Limitations
- The macOS/iOS Xcode toolchain is not available in this environment. Swift parsing was checked locally, but an actual iOS compile is **not** verified; Codemagic is the compiler test.
- Neither an API-accepted request nor Roam Core Location callback independently proves what Apple Maps displays.
- No indefinite background task, silent-audio workaround, or VPN change has been introduced.
- No pairing credentials should be shared with debug reports.
