# Roam v0.19 — finite background reliability trials

## Purpose
This experimental build extends the **working v0.18 source** with optional 90-second, 120-second and 300-second trials. The 20-, 30- and 60-second experiments remain available. The existing developer tunnel, pairing and re-teleport implementations are unchanged.

## Build (Windows + GitHub Desktop + Codemagic)
1. Back up the v0.18 source and working IPA.
2. Create a new GitHub branch called `roam-v0.19`.
3. Copy the contents of the full-source ZIP to the root of the repo (not into a nested folder).
4. Commit and push the branch.
5. In Codemagic, select workflow `roam-ios-unsigned` and confirm the branch is `roam-v0.19`.
6. If successful, download `roam-v0.19-unsigned.ipa`; install using the user's established signing/iLoader workflow.
7. Verify the build's reported version is **0.19.0 (19)**.

## Experimental test sequence
1. Begin with a successful Wi-Fi-assisted teleport, keep LocalDevVPN and the simulation session active, then turn Wi-Fi fully off and verify a retained re-teleport on cellular.
2. Set Drive speed and repeat a 60-second finite background cruise. After a couple seconds, open Apple Maps and observe its blue dot. Return to Roam and export diagnostics.
3. If 60s remains reliable, test **90 seconds**, then **120 seconds**. The **5-minute** test is optional and should only follow shorter successful tests.
4. Run one experiment at a time. Do not force quit Roam, press Stop, or start a new paired handshake during a trial.
5. In diagnostics compare planned duration, measured wall-clock duration, background-state wall-clock duration, background API attempts/accepts/failures, command gaps >2.5s, task expirations and end reason. Check Apple Maps separately.

## Important constraints
- `beginBackgroundTask` is a *finite* request to finish existing work, **not** a promise of 5 minutes of execution. An expiry stops the experiment; v0.19 never attempts to renew background tasks automatically.
- Trials stop after a timer gap over 10 seconds rather than claim smooth GPS movement. Requested distance and successful developer-service API responses are **not** independent measurement of real system-wide location; Apple Maps visual observation remains separate evidence.
- The standard cruise/joystick background policy and Wi-Fi-initialised session pathway are unchanged. Fresh cellular-only initial developer pairing is still unresolved.
- No on-device build has been executed here; Xcode/Codemagic is the decisive compiler check.
