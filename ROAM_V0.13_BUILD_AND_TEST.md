# Roam v0.13 — GPS movement diagnostic build

**Source build:** v0.13.0 (13). **Starting point:** supplied v0.12.0 source (the version which was reported working for Wi-Fi-to-4G retained-session re-teleportation). **Status:** Syntax-parsed and project configuration checked in a Linux environment; not compiled with Apple's iOS SDK and not installed or verified on an iPhone here. Codemagic must build and iLoader must sign/install the app.

## What changed

- **Step 200 m N:** One deterministic command computes a coordinate 200 metres north of Roam's last API-accepted simulated coordinate. This calls the existing `LocationEngine.set` code through the **retained session**; it does **not** clear the session or start a fresh tunnel. Requires an existing simulated location and handle.
- **Hold position:** Stops joystick/route activity and leaves the last simulated coordinate unchanged. Does not repeatedly re-send a position, keep iOS running indefinitely, or prevent iOS from ending a developer tunnel.
- **Movement diagnostics:** New read-only panel showing attempted, API-accepted, failed commands; last requested and last API-accepted coordinates; the last asynchronous CoreLocation callback seen by Roam; a bounded last-60-command log; and last engine stage and error. Copy report is user-initiated and can include **coordinates**—review before sharing.
- **Compact joystick:** Shrinks the joystick footprint and lets you choose left or right alignment while open. It reports the latest API result. Stopping movement does not clear GPS.
- **Joystick start guard:** A failed first simulation no longer leaves the joystick in an apparently active state.
- **Build metadata:** `MARKETING_VERSION=0.13.0`, `CURRENT_PROJECT_VERSION=13`, `roam-v0.13-unsigned.ipa` artifact.

## Preserved from v0.12

- The idevice/RPPairing/RSD and LocationEngine code, including the **same target tunnel address and port**, is unchanged. The existing simulation handle is reused when available.
- Re-teleport, explicit End Simulation, LocalDevVPN candidate detection, TCP/paired handshake diagnostics, and Wi-Fi-to-cellular handover procedures remain in place.
- Existing bundle identifier is **`com.roam.beanywhere.cellularresearch`**. An install with the same identifier may replace an older experimental Roam version; safeguard v0.12 source and build artifact first.
- Neither Roam nor v0.13 claims a fresh developer tunnel can be opened on cellular-only connectivity. Your prior tests demonstrated that this is still failing.

## Installation: Windows → GitHub Desktop → Codemagic → iLoader

1. Save a copy of the **working v0.12 source ZIP and IPA**, as well as your current Codemagic build. Keep the LocalDevVPN installation intact.
2. In GitHub Desktop open the Roam repository. Create a new branch `roam-v0.13` from `roam-v0.12` if possible. **Do not overwrite** the v0.12 branch.
3. Extract `Roam_v0.13_FULL_SOURCE.zip` and copy its **contents** (not an extra enclosing folder) into the local repository root. Review changes, commit, and Publish branch. Alternatively, apply the patch ZIP at the repository root over v0.12.
4. In Codemagic select `roam-v0.13`, workflow **`roam-ios-unsigned`**, and start the build. Verify the build prints `Built Roam 0.13.0 (13)`.
5. From Codemagic **Artifacts** download `roam-v0.13-unsigned.ipa`. Sign and install through your existing iLoader procedure. It is **not** pre-signed in the source download.
6. On iPhone open Roam → Settings and confirm **0.13.0 (13)** before starting tests. The previous pairing file may need importing again if signing changes the bundle ID or app container. Never commit pairing credentials, signing material, or provisioning profiles to GitHub.

## Controlled iPhone test

1. **Baseline:** Turn Wi-Fi ON and Mobile Data ON, connect LocalDevVPN, teleport to a known destination in Roam, and confirm the blue dot in **Apple Maps**.
2. **Handover:** Without pressing Stop or starting a new handshake, turn Wi-Fi fully OFF in iPhone Settings. Verify mobile data is working. Re-teleport to a second destination and confirm it in Apple Maps. If this fails, **stop here** and report the error; v0.13 should not change the baseline.
3. **GPS Step:** Without stopping the simulation, press **Step 200 m N** exactly once. Open **GPS movement diagnostics** and note whether the event says **API accepted** or **Failed** and the requested/accepted coordinates. Then switch to Apple Maps and check whether the location moved approximately 200 m north from its previous simulated location. The API result alone does not prove Apple Maps moved.
4. **Hold Position:** Tap **Hold position**; do not use End Simulation. Observe whether the simulated location remains in Apple Maps. This control does not itself issue a fresh GPS command.
5. **Joystick:** Return to Roam; tap Move, optionally switch the compact joystick between left and right. Choose Drive speed. Hold the joystick in one direction for 15–20 seconds. Release, tap Hold position, then inspect Apple Maps. Open the diagnostics panel and look for failed joystick commands; if there are none, iOS/Apple Maps may still behave differently.
6. If the results are unclear, tap **Copy diagnostic report** and share the **text after reviewing the coordinates and error detail**. Do not share pairing files, Apple credentials or certificates. The diagnostics do not automatically upload anywhere.

## Diagnostic meaning

- **API accepted** means `location_simulation_set` returned without an FFI error. It is not independently confirmed by iOS Maps.
- **Roam CoreLocation callback** is the latest update given to Roam's `CLLocationManager`. It may be stale or already simulated; it is **not independent proof** of system-wide location changes.
- **Retained location handle present** means Roam still holds a reference; it does not certify that the connection is alive.
- **Hold position** pauses movement; it cannot guarantee that the operating system continues maintaining the simulated position.
- **New session over 4G/5G** remains unproven. Avoid clearing a working retained session until you are ready to re-establish it via Wi-Fi if needed.

## Development QA / rollback

All Swift files were tested using `swiftc -frontend -parse` in Linux, and the Codemagic output metadata was checked for version and filename consistency. The availability and behaviour of SwiftUI, MapKit, and the bundled iOS static library cannot be fully type-checked here. Codemagic's Xcode build is the first authoritative compile/link test.

If Codemagic fails, retrieve `roam-build.log` and send the **first actual Swift compiler or linker error**, not only the last line. Revert to the v0.12 branch/source if v0.13 behaves differently during the handover test.
