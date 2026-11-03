# Roam v0.11 — Persistent-Session Teleport Experiment

**Status:** Experimental source. Swift syntax parsed successfully in a Linux Swift compiler. **Not built with Apple's iOS SDK or tested on an iPhone.** This is not proof that a new teleport will work over active 4G/5G.

## Why this experiment

User confirmed: an ongoing simulated location can survive after switching Wi-Fi OFF / mobile data ON and joystick updates can be reflected in Apple Maps even with poor or unusable cellular internet. But pressing the former red **Stop** button ends the simulation and a new paired tunnel cannot be started under active cellular.

The v0.10 engine already tries `location_simulation_set` on its retained simulation handle, instead of reopening the developer tunnel. The *interface*, however, **removed the Teleport button while `session.isSpoofing` was true**, replacing it with **Stop** (`location_simulation_clear` and cleanup). This prevented an easy on-device test of re-teleporting through the existing handle.

## Changes

1. **Re-teleport stays visible while a session is active.** Drop or select a new destination pin and press Re-teleport. It reuses the existing location simulation handle when present, without calling `clear()` first.
2. **Pause movement** halts joystick and route tasks while preserving the simulated location and connection. The explicit **End simulation** action has a confirmation dialog because it can make new cellular teleports impossible until Wi-Fi is available again.
3. **Avoid route/joystick override of teleport** by pausing active movement before sending the new destination.
4. **Do not dispose of the retained handle on a failed location-simulation clear.** The user can retry after restoring connectivity; a transient failed clear no longer destroys the only handle.
5. UI shows whether a teleport was *sent via a retained handle* or initiated a new session. **This confirms only the local API call's return status; verify actual device GPS in Apple Maps.**
6. Build version updated to **0.11.0 (11)**, retaining the distinct experimental `com.roam.beanywhere.cellularresearch` bundle ID from v0.10. The original v0.9 and LocalDevVPN must remain untouched.

## Files changed (relative to v0.10)

- `Locus/Engine/LocationEngine.swift`
- `Locus/Engine/SpoofSession.swift`
- `Locus/Features/Map/RootView.swift`
- `Locus.xcodeproj/project.pbxproj`
- `project.yml`
- `codemagic.yaml`

## Install on Windows/GitHub Desktop

1. In GitHub Desktop, select repository **Roam** and switch to `roam-v0.10` before creating a **new branch `roam-v0.11`**. Do not edit `roam-v0.9`.
2. Extract **Roam_v0.11_Persistent_Teleport_Patch.zip** and copy its replacement `Locus` directory and project/config files **into the existing Roam repository**, allowing overwrite of the six listed files. Do not copy the `README` as a replacement for unrelated files.
3. GitHub Desktop → Commit to `roam-v0.11` → Publish branch.
4. Codemagic → Roam project → choose `roam-v0.11`, workflow `roam-ios-unsigned`; use the existing unsigned build and iLoader signing/install procedure from v0.10.
5. Verify app version **0.11.0**, and that the original Roam v0.9 and original LocalDevVPN are still installed. If the signing tool assigns a different bundle ID, the app may have a new sandbox and require a new pairing import; avoid using another free provisioning slot unnecessarily.

**Alternative:** `Roam_v0.11_Persistent_Teleport_Full_Source.zip` is a complete v0.11 snapshot based on the provided v0.10 source.

## Test — one controlled sequence

1. On Wi-Fi: connect ORIGINAL LocalDevVPN, open experimental v0.11, ensure pairing file present, perform an initial teleport and verify Apple Maps follows.
2. Turn Wi-Fi OFF while leaving the session active. Turn Mobile Data ON; record whether internet genuinely works by opening a new web page separately.
3. **Do not press End simulation.** Select a *different* point in Roam and tap **Re-teleport**; observe whether Apple Maps moves to that second destination.
4. If successful, repeat to a third point without ever ending the simulation. Check whether the status reports `Persistent teleport sent through the retained session`.
5. Press **Pause movement** to verify it does not end the simulated GPS. Only when finished, use **End simulation** to restore normal GPS. If ending fails, regain Wi-Fi and retry; verify actual GPS before relying on navigation or location sharing.

## Important limitations

- A `location_simulation_set` success may reflect a successful local command write **without proving** Apple Maps applied it. External observation is essential.
- Still no proof of functioning initial pairing, teleport, or retained commands with reliable cellular internet; one bar or a 5G icon is insufficient to verify usable mobile data.
- Apple may terminate the underlying session after network transition. This build does not defeat iOS entitlement restrictions or Apple policy.
- Don't publish pairing files, device identifiers, diagnostic logs with personal data, or novel unpublished methods.
