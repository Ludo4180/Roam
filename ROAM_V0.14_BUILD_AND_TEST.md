# Roam v0.14 — Continuous GPS movement and session diagnostics

**Source version:** 0.14.0 (build 14)  
**Starting point:** the previously created working v0.13 full-source project.  
**Validation:** All Swift source files passed `swiftc -frontend -parse` on Linux, and project/version/artifact names were checked. The project has **not** been compiled with Xcode/iOS SDK or tested on the user's iPhone in this environment. Codemagic must perform the actual compile and link.

## What changed in v0.14

- **Continuous joystick cadence:** reduced the movement command target from four requests/second to one every 0.8 seconds; each successful step uses elapsed monotonic time rather than assuming every timer event arrived precisely on schedule. Long scheduling gaps are capped at 1.2 seconds to avoid a large location jump after an app stall.
- **Movement diagnostics:** counts API-accepted and failed *continuous movement* commands and the distance calculated from accepted requested increments. Logs timing and requested step distance per API call alongside prior v0.13 event diagnostics.
- **Hands-free, 20-second northward trial:** select a travel mode (Drive is useful for a visible change), then tap **Move north for 20s**. Roam sends repeated incremental location updates while the app is visible, and stops automatically without clearing the last simulated position. This uses the **same `LocationEngine.set` / `apply` path** as the v0.13 200 m step, with the existing retained session only. You can then open Apple Maps and check the blue dot without having to hold down the joystick while switching apps.
- **Safer foreground lifecycle:** if Roam enters the background during joystick or timed movement, the app pauses those controls and retains the last accepted simulated coordinate; **it does not end the location simulation**. The existing developer connection is not forcibly cleared or reopened.
- **Error policy:** if a continuous movement update fails, automated movement stops and reports the failure. It does not silently trigger a fresh developer-tunnel handshake over cellular or clear the existing handle.
- **Diagnostics copy:** now includes last continuous status, attempted/accepted ticks, computed API-accepted movement distance, and cruise status.

## Specifically preserved

`Locus/Engine/LocationEngine.swift`, `Locus/Features/Settings/CellularResearchView.swift`, `Locus/Support/LocalDevVPN.swift`, and the vendor `libidevice_ffi.a` are byte-for-byte identical to v0.13. The v0.12/v0.13 retained-session logic, 200 m north step, Re-teleport, explicit End Simulation, pairing, map, and route features are preserved. The project continues using bundle ID `com.roam.beanywhere.cellularresearch`.

**Important:** a successful movement command means Apple's developer-service API returned success; it is **not** independent proof of system-wide movement. Check Apple Maps after the hands-free trial. Neither this build nor iOS guarantees a developer tunnel can be initially established via cellular-only networking. The established Wi-Fi-to-4G handover remains the controlled starting procedure. No background joystick service is claimed.

## Windows → GitHub Desktop → Codemagic → iLoader

1. Save your working **v0.13 source, installed IPA and existing Codemagic build**. Keep LocalDevVPN installed.
2. In GitHub Desktop select your Roam repository and create branch `roam-v0.14` from `roam-v0.13` (or the branch that contains v0.13).
3. Extract `Roam_v0.14_FULL_SOURCE.zip`, then copy its **contents directly into the repository root**. Do not add an extra enclosing folder. Alternatively, overlay `Roam_v0.14_PATCH_FROM_v0.13.zip` onto the v0.13 root.
4. Commit your changes and publish `roam-v0.14`.
5. In Codemagic select the branch and run workflow **`roam-ios-unsigned`**. The expected verified output is `Roam 0.14.0 (14)` and artifact **`roam-v0.14-unsigned.ipa`**.
6. Download the unsigned IPA from Codemagic artifacts. Sign/install via the same working iLoader setup you used for v0.13. It may replace the previous experimental Roam installation because the bundle ID is unchanged. **Do not uninstall LocalDevVPN.**
7. On the iPhone, check Roam Settings for version `0.14.0 (14)`. If build fails, share the **first Swift compiler/linker error** in `roam-build.log`.

Do not upload pairing files, provisioning profiles, passwords, or Apple certificates to public GitHub branches. The movement diagnostic report contains precise requested coordinates; inspect before sharing.

## Test sequence — v0.14

1. **Baseline:** enable Wi-Fi and mobile data, connect LocalDevVPN, then perform a known good Teleport. Confirm Apple Maps shows the simulated coordinate.
2. **Cellular handover:** keep the session active, fully disable Wi-Fi in Settings, and confirm cellular data works. Select another destination and press **Re-teleport**. Confirm Apple Maps. If this baseline fails, stop here and report it; v0.14 should not alter the proven route.
3. **20-second continuous trial:** while still on cellular, select **Drive** speed, keep Roam foregrounded, then tap **Move north for 20s**. Let it finish with Roam visible. Check `GPS movement diagnostics`: look for accepted ticks, any errors, and computed distance. A clean 20-second drive trial would typically command roughly 250 metres; precise distance depends on timer scheduling and whether all API calls succeed.
4. **Apple Maps verification:** after the button changes back from Stop to Move, open Apple Maps. Check whether the blue dot moved north by a corresponding amount. The displayed API-accepted metres are **not** a GPS measurement.
5. **Joystick:** return to Roam; tap **Move**, choose Drive, drag fully north for 15–20 seconds, then release the joystick. Note the movement diagnostic count, tap **Hold position**, and compare Apple Maps. Holding zero input sends no commands. If app backgrounding occurs during movement, the app should pause movement rather than pretend it is still sending updates.
6. If anything fails, open Movement diagnostics and copy the report after checking it contains no information you want to keep private.

## What to report after testing

- Did initial Wi-Fi Teleport and 4G Re-teleport both still work?
- Did **Move north for 20s** finish with accepted updates and no failures, and approximately how many API-accepted metres were shown?
- Did Apple Maps' blue dot move correspondingly? Did joystick movement independently show the same effect?

## Known limitations / rollback

- This version does not solve initial 4G-only developer pairing/RSD connection.
- The joystick is not a guaranteed background movement service. iOS can suspend apps and developer connections. When Roam is backgrounded, movement control is deliberately paused.
- The existing synchronous FFI call can still make the UI temporarily unresponsive if developer communication stalls; the slower command cadence reduces frequency but does not eliminate that risk.
- An API-accepted update and Roam's own Core Location callback do not independently confirm Apple Maps. Test there.
- Use your saved v0.13 Codemagic branch/build for rollback if v0.14 behaves worse.
