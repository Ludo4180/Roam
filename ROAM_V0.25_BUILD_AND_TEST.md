# ROAM – BE ANYWHERE — v0.25 build and on-device test

## Objective

Preserve the confirmed Wi-Fi-free developer-GPS startup sequence from v0.24, while removing the routine manual trip to Settings for switching cellular data OFF and back ON. **This is Shortcuts-assisted, not direct cellular control.** It requires the *original LocalDevVPN already connected*, Wi-Fi disabled, user-created Shortcuts, and a previously selected map pin. A free Apple ID is still sufficient for the user's existing unsigned-Codemagic/iLoader pipeline; no custom packet-tunnel extension is included.

## Changes in v0.25

- New **ONE-TAP START ASSISTANCE** section in the existing Settings/map **Wi-Fi-free startup** guide.
- One explicit tap arms **a single** teleport to the *currently selected* destination, then requests Apple's **Roam Data Off** Shortcut via Apple's documented `shortcuts://run-shortcut?name=` URL scheme.
- The pending teleport is **in memory only**; no persistent automatic startup setting. When Roam returns to the foreground, **within 90 seconds**, and its NWPathMonitor reports offline, it sends a **single** location command. The arm clears *before* that command; no repeated auto-teleports from network/lifecycle changes.
- The app provides **Cancel armed teleport**, a prominent **Restore mobile data** Shortcuts button, live status and accepted/failed API-result text.
- Network-path observations and a detected VPN-like interface are **not verification** of radio toggles, VPN ownership, nor Apple Maps location. Confirm them independently.
- The fully manual workflow from v0.24 stays available, including manual teleport. No automatic VPN reset, background change, change to pairing files, altered engine, joystick, or background cruise.
- User creates Shortcuts themselves. Roam only asks iOS to *run an existing named Shortcut*; it does not install a Shortcut or directly toggle cellular data.

## Create the two iPhone Shortcuts **before testing**

In iPhone **Shortcuts**, tap **+** for each of the following and use *exactly* these names:

### First: `Roam Data Off`
1. Add action **Set Cellular Data** / **Set Mobile Data** (wording varies by locale). Set the action to **Turn Off**, *not Toggle*.
2. Add action **Open App**, choose your installed **Roam**.
3. Save the Shortcut named **Roam Data Off**.

### Second: `Roam Data On`
1. Add action **Set Cellular Data** / **Set Mobile Data** and set it to **Turn On**, *not Toggle*.
2. Add action **Open App**, choose your installed **Roam**.
3. Save the Shortcut named **Roam Data On**.

Test **both Shortcuts manually** before trying the one-tap procedure. They should set cellular data OFF/ON and return to Roam. If the action names differ, search for *cellular* or *mobile data*; if an action is unavailable, use the fully manual Settings method. Do not add a Wait-for-network action to the OFF Shortcut, as that could stall while offline. Do not create a shortcut that resets/disconnects VPN.

## Codemagic build from Windows

1. **Save your known-good v0.24 source and IPA.** Use a separate GitHub branch `roam-v0.25`.
2. Extract `Roam_v0.25_FULL_SOURCE.zip` into your GitHub Roam project root, replacing its contents. You should see `Locus.xcodeproj`, `project.yml`, `codemagic.yaml`, and `Vendor/idevice` in the same root. Alternatively overlay the v0.25 patch on a CLEAN v0.24 source tree.
3. Commit and push. In Codemagic run the workflow named **`roam-ios-unsigned`**. (The YAML display name now includes v0.25.)
4. Ensure the release version reads **0.25.0 (25)** and the artifact is **`roam-v0.25-unsigned.ipa`**.
5. Install with your existing working iLoader signing method. This is an unsigned IPA until you sign it; do not remove your v0.24 backup.

## iPhone regression testing

### A. Confirm the original method still works

1. Confirm LocalDevVPN already connected using cellular data, **Wi-Fi OFF**.
2. Turn cellular data OFF manually in Settings. Launch Roam and select a pin on the map; use the ordinary Teleport button.
3. Verify Apple Maps blue dot mirrors the target. Restore data manually; try another teleport with 5G ON and Wi-Fi OFF.
4. The GPS engine and movement code should behave exactly like v0.24. Verify a short optional background cruise later, without stopping a working session just for a diagnostic.

### B. Test optional one-tap Shortcuts assistance

1. End a previous Roam session only if you are deliberately preparing a *fresh* startup test. Confirm original LocalDevVPN says **Connected** in iPhone Settings. Keep **Wi-Fi OFF, cellular data ON**.
2. In Roam select a **new pin on the map**. Open **Wi-Fi-free startup guide** (lightning icon or Settings).
3. Tick **I checked LocalDevVPN is Connected**. Verify the network indicator says **Cellular active**, and press **One-tap: Go offline & start teleport**.
4. Shortcuts should execute **Roam Data Off**, disable cellular data and open Roam. When the path reads offline **within 90 seconds**, Roam sends exactly one teleport request. If the app does not return automatically, return manually within 90 seconds; if it timed out, use the ordinary Teleport button instead.
5. Look for **One-shot teleport request accepted**. This means *the local GPS API accepted it*, not independently that Apple Maps has moved.
6. Verify in Apple Maps. Return to the Roam guide and press **Restore mobile data — Run ‘Roam Data On’**. Verify cellular connectivity comes back, Wi-Fi stays OFF, and Apple Maps remains at the simulated location. Re-teleport normally with cellular ON.

### C. Failure cases and safety

- No installed Shortcut / name mismatch: Shortcuts may show an error. The app cannot tell whether the named Shortcut actually exists. Use iPhone Settings to restore data if necessary; cancel pending teleport or wait 90 seconds for automatic expiry.
- VPN disconnected: do not start; reconnect it **while cellular is ON** first. VPN interface candidate is not confirmation of an established developer tunnel.
- `Network path` stays `Cellular active` on return: Roam will **not** auto-teleport. Check the OFF Shortcut or use manual radio settings and Teleport.
- `Network path` reports offline while cellular is ON (unusual path state): the monitor cannot validate actual radio toggles. The feature assumes you configured and tested the Shortcuts correctly; do not treat the network indicator as definitive.
- Returning after **90 seconds**: pending auto-teleport is cancelled. Press the button again to start over; no delayed surprise teleport.
- Dismissing guide or iOS terminating/restarting Roam: auto-teleport state is lost. A later startup will not auto-teleport without a fresh explicit tap.
- If either Shortcut fails, use iPhone Settings > Mobile Data to get back online. A separate **Restore mobile data** button remains available in the guide even when teleport fails.

## Verified in the build environment vs still unverified

- Linux `swiftc -frontend -parse` checks Swift **syntax only**, not Apple SDK type-checking or runtime behavior.
- Project and Codemagic config/version consistency and ZIP integrity are verified locally.
- The actual Xcode iOS build, native Shortcuts availability, app switching, and on-device one-tap teleport must be verified in Codemagic and on your iPhone.
- **No GPS engine, pairing, or VPN packet-tunnel changes** were made. Keep pairing credentials private.

## Apple documentation

- Run a shortcut from a URL: https://support.apple.com/en-au/guide/shortcuts/apd624386f42/ios
- Launch an app from Shortcuts using Open App: https://support.apple.com/en-gb/guide/shortcuts/apdaf74d75a5/ios
