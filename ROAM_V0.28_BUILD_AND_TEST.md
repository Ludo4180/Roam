# Roam v0.28 — Cold Start stability & interface refinement

**Baseline:** The user-confirmed Roam v0.27 Codemagic-fixed full source, including the verified three-Shortcut Cold Start flow. **Status:** source prepared and locally parsed; actual Codemagic/iPhone testing required. Preserve a working v0.27 backup.

## What changed

- Clearer, compact live **startup state card** above the original checks. Distinguishes idle, armed return, GPS API accepted, cellular-path return and already-active GPS sessions. These are observations/indicators, not guarantees that Apple Maps moved.
- The previously tested **Cold Start** now appears as the primary working path; the VPN-connected One-Tap fallback is retained. The app **still requires original LocalDevVPN installed** and a user-created **Roam Cold Start** Shortcut. This does not remove the VPN dependency.
- After an accepted GPS command, an optional, explicit **Apple Maps matched / did not match** confirmation helps separate local API acceptance from independent GPS observation. The app does not inspect Apple Maps itself. Counts stay on the device and are never uploaded.
- On a startup failure, timeout or manually reported Apple Maps mismatch, a prominent **recovery card** offers Restore Mobile Data and Open LocalDevVPN, without deleting pairing, disconnecting a retained session or silently changing radios.
- A collapsed **three-clean-start reliability test** describes a repeatable manual test including restoration, re-teleport and background cruise.
- Diagnostics now provide **Copy safe startup summary** to the clipboard: timestamp, non-secret state flags and aggregate counters ONLY; excludes RPPairing content, credentials, coordinates and tunnel addresses. Check clipboard handling if sharing externally.
- Updated visible version strings in Settings and Shortcuts help; project.yml, project.pbxproj and Codemagic verify **0.28.0 (28)** consistently.

**Unchanged:** All GPS simulation, retained session, background cruise, developer tunnel, RPPairing, VPN integration and route research engine files; no new entitlements or VPN extension. No new automatic changes to the iPhone's radios or VPN profiles.

## Build with GitHub and Codemagic

1. Make a backup of your **user-tested Roam v0.27** source and installed IPA.
2. Create branch `roam-v0.28` in your existing repository. Extract `Roam_v0.28_FULL_SOURCE.zip` **into the repository root**, merging/replacing files but not deleting `.git`. If you are definitely starting with **v0.27 Codemagic-fixed source**, apply `Roam_v0.28_PATCH_FROM_v0.27.zip` instead.
3. Commit and push to GitHub.
4. Choose existing `roam-ios-unsigned` in Codemagic and build the branch. The macOS script checks `CFBundleShortVersionString=0.28.0` and `CFBundleVersion=28`; a previously encountered 26/27 verification mismatch is explicitly guarded against.
5. Download `roam-v0.28-unsigned.ipa`, sign/install with the same working iLoader procedure as before.
6. The package contains **source**, not a ready signed IPA. Do not uninstall working v0.27 until on-device tests pass.

## Update all three iPhone Shortcuts

Because multiple versions of Roam are installed, open each Shortcut and make sure **Open App** selects the *new v0.28 installation*.

- **Roam Cold Start:** Set VPN → Connect → LocalDevVPN (select its actual VPN profile) → Wait 5s → Set Cellular Data OFF → Open App Roam v0.28.
- **Roam Data Off:** Set Cellular Data OFF → Open App Roam v0.28.
- **Roam Data On:** Set Cellular Data ON → Open App Roam v0.28.

Use the exact Shortcut names. Preserve existing working actions; no need to recreate from scratch. Shortcuts may display its own UI/confirmation prompts. Roam does **not** directly control the VPN or cellular setting.

## First iPhone tests

1. **Baseline regression:** With Wi-Fi OFF, LocalDevVPN connected and cellular ON, run the established **One-Tap** method. Observe one accepted teleport in Roam and verify independently in Apple Maps. Restore cellular, re-teleport and verify.
2. **Cold Start from disconnected VPN:** Stop any simulation (only when intentionally testing), set Wi-Fi OFF and cellular ON, disconnect LocalDevVPN **without deleting its VPN profile**, choose a map pin, then use Cold Start. The Shortcut should connect the VPN, wait, turn data OFF and return to Roam. Roam should accept one new teleport; **check Apple Maps**.
3. **Restore/retention:** Use the same Data On flow that worked in v0.27, verify cellular service and re-teleport with Wi-Fi still OFF.
4. **Independent verification:** After a new accepted API command, tap the new *Apple Maps matched* (or *did not match*) button only after personally checking its blue dot. These counters are user observations, not automatic GPS telemetry.
5. **Reliability:** Repeat the full disconnected-VPN Cold Start 3 times on separate deliberate attempts; track failures and manually observed Apple Maps results. Then repeat a short and a five-minute background cruise; independently check Apple Maps during background movement.
6. **Failure recovery:** In a deliberately failed or interrupted run, confirm the Restore Mobile Data button remains usable and Roam does not clear pairing or a retained location session. Do not intentionally interrupt a session you need.
7. **Diagnostics:** Expand `Diagnostics, statistics & manual steps`, use `Copy safe startup summary`, check it contains **no coordinate, pairing or endpoint value**, and share it only if needed.

## Cautions and limitations

- `NWPathMonitor` and `utun` candidate detection are indicators, not a route table or proof LocalDevVPN owns the interface.
- "GPS API accepted" does **not** mean Apple Maps definitely moved; the manual verification action is intended to record that separate observation.
- **LocalDevVPN is still installed and required**, though the successful v0.27 Shortcut removed the manual step of connecting it first.
- An unsigned Codemagic IPA must still be provisioned/signed via your established iLoader process. Linux Swift syntax parsing cannot validate iOS SDK type checking or signed-device execution.
- No change to background execution permissions, and no guarantee of indefinite background cruise: test against Apple Maps before relying on longer trips.
- If v0.28 fails, restore v0.27 rather than deleting LocalDevVPN, resetting pairing or rewriting engine settings.
