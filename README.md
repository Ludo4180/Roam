# Roam v0.28 — stable Cold Start and startup verification

Built directly from **Roam v0.27 Codemagic-fixed full source** (the user-tested Cold Start baseline). New: a compact live startup state, user-confirmed Apple Maps result counters, failure recovery actions, safe diagnostic summary copying, and a three-run reliability plan. The proven v0.27 Shortcuts flow and all GPS, pairing, VPN, movement, and background-cruise engine files are unchanged.

**Read [`ROAM_V0.28_BUILD_AND_TEST.md`](ROAM_V0.28_BUILD_AND_TEST.md) before installing.** The v0.28 Codemagic output should be `roam-v0.28-unsigned.ipa`. Use the unchanged iLoader signing procedure and update all three Shortcuts to **Open App → new Roam v0.28**.

The installed **original LocalDevVPN is still required**; Cold Start automates its *connection*, not its replacement. A successful GPS API return is not proof of independent Apple Maps movement; v0.28 adds a separate user-controlled verification count. Do not remove the working v0.27 backup.

---

## Earlier version notes (retained for history)

# Roam v0.26 — optional assisted cellular restoration

Built directly from the user-tested **Roam v0.25** source. This version preserves the established Wi-Fi-free startup procedure, with the **original LocalDevVPN already connected**. All underlying GPS, pairing, VPN-integration, joystick, route and background-cruise engine files are unchanged.

## What changed

- A new, **OFF by default**, non-persistent switch in the Wi-Fi-free Startup guide: **Automatically run Data On after accepted teleport**. When explicitly enabled for that attempt, Roam runs your *existing* `Roam Data Off` Shortcut, waits until the network observer reports offline after app return, and sends exactly one teleport request as in v0.25. **Only if the local GPS API accepts the teleport**, Roam waits two seconds in the foreground and then opens the user-created `Roam Data On` Shortcut. The hand-off is cancelled if the app leaves the foreground, the view closes, a failure is reported or the user cancels it. Normal manual restore remains available at all times.
- Prominent manual **Restore mobile data now** action appears after a locally accepted one-shot teleport when still offline.
- Separate status when the user returns after running the Data On Shortcut. A cellular path as reported by `NWPathMonitor` is an **indicator**, not proof the cellular setting was actually switched, and API acceptance is **not** proof of Apple Maps movement.
- Small privacy-conscious, local-only counters: one-tap attempts, API accepted/failed, Data On Shortcut launches and observed cellular-path returns. Reset control included. No coordinates, IP addresses, RPPairing data or other secrets are retained by this new instrumentation.
- Recovery guidance for when the original VPN is disconnected or a Shortcut fails. Restoring mobile data manually remains possible even after any failed auto-teleport.

No modification to the LocalDevVPN application, Apple VPN entitlements, location engine, or RPPairing files. Roam does not independently change cellular/Wi-Fi settings, nor can it confirm the Shortcuts ran successfully: the existing Shortcuts explicitly configured by the user perform those actions.

## Demonstrated baseline — v0.25 on the user's iPhone

With Wi-Fi OFF, the original LocalDevVPN already connected and cellular data initially ON, Roam successfully invoked `Roam Data Off`, returned offline, automatically teleported once and showed the new simulated location in Apple Maps. The user also confirmed using `Roam Data On` and re-teleporting with cellular restored. **v0.26's automatic second Shortcut launch is new and has not been tested on a device.**

For the safest first v0.26 test leave the new toggle OFF and verify the old manual-restore sequence, then separately opt in to the new automatically launched restore Shortcut. Do not remove the v0.25 backup until the new build passes on-device tests.

Build via the existing Codemagic workflow `roam-ios-unsigned`. Expected file: `roam-v0.26-unsigned.ipa` (you still sign with your established iLoader method). See `ROAM_V0.26_BUILD_AND_TEST.md`.

## Important constraints

- Correctly named user-created Shortcuts `Roam Data Off` and `Roam Data On`, both ending in **Open App → new Roam installation**.
- Wi-Fi OFF; original LocalDevVPN **already connected** prior to taking cellular data offline.
- A selected map pin and pairing file installed. Keep the proven v0.25 IPA/source in backup.
- Full cold-start pairing with LocalDevVPN disconnected over cellular is **not** demonstrated.
- The v0.26 optional hand-off is experimental; normal Shortcuts may show their own system UI. No guarantee of uninterrupted or fully background-automatic execution.

Earlier cellular routing diagnostics and finite background movement experiments remain available in their unchanged source locations.

## Roam v0.27 — Cold Start experiment

See [`ROAM_V0.27_BUILD_AND_TEST.md`](ROAM_V0.27_BUILD_AND_TEST.md) for the optional `Roam Cold Start` Shortcut that requests iOS to connect the installed LocalDevVPN VPN profile before temporarily disabling cellular data. New UI groups tested v0.26 startup, experimental VPN-disconnected startup, and collapsible diagnostics. GPS/paired developer engine remains unchanged. The cold start feature is **not proven until iPhone tests** and still requires the original LocalDevVPN app.
