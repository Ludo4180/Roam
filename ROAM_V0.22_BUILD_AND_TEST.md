# Roam v0.22 — Cellular-only developer connection audit

**Based on:** User-confirmed working Roam v0.21. **Build ID:** 0.22.0 (22). **Codemagic workflow:** `roam-ios-unsigned`. **Artifact:** `roam-v0.22-unsigned.ipa`.

## Purpose

Find out why a **fresh** developer-service session cannot be established over cellular, without changing the working location simulation or background cruise engine.

The full source is a source code project, **not an IPA**. Code has been syntax-parsed, but requires compilation and installation in Codemagic and iLoader. This release is a diagnostic experiment, **not a confirmed Wi-Fi-free GPS fix**.

### New controls

**Settings → 5G startup / pairing-port audit** (formerly Cellular research):

- **Discover pairing service port:** Browses `_remotepairing._tcp` using the OS's Bonjour browser for six seconds. It may return more than one device. **Verify the device name** before selecting a port. The standard `49152` is only a fallback; iOS may assign another port. Discovery may be unavailable while Wi-Fi is off.
- **Use port ... for next new session:** Stores the chosen port using Roam's existing `TunnelConfig` mechanism, but only when there is no active simulation. It does **not** re-pair or end a simulation.
- **Run paired VPN vs loopback audit:** With a pairing file and no active spoofing session, sequentially compares TCP connectivity and actual RPPairing + RSD handshakes on `10.7.0.1:<saved port>` and `127.0.0.1:<saved port>`; each stage is reported. No GPS commands are invoked.
- **Copy diagnostic report:** Includes detected network path, test port, advertised service names, and precise errors; **does not** copy device pairing credentials or full GPS coordinates.

## Controlled test sequence

1. **Preserve the v0.21 IPA and source.** Confirm v0.22 can still teleport when Wi-Fi is joined, and that a retained session still re-teleports on 5G. Do **not** end a working session merely to run this audit if you need it later.
2. For a *fresh-session* test, end simulation normally while Wi-Fi is ON. Under Settings → 5G startup / pairing-port audit, run port discovery. If there are results, check whether the advertised name belongs to **this** iPhone. Record the port; if different from the saved value, select it for future sessions. Do not select a nearby device's service.
3. Turn Wi-Fi OFF in iPhone **Settings** (not just Control Centre); leave 4G/5G ON and connect LocalDevVPN. Make sure the app has a pairing file and no simulation is active.
4. Run **Run paired VPN vs loopback audit**. This attempts developer protocol authentication without GPS. Copy the results. If an RSD handshake succeeds over either endpoint, we have a concrete candidate for the next test. If VPN peer fails while loopback TCP succeeds, the TCP listener is not enough — inspect the paired result.
5. **Only if a paired RSD handshake succeeds:** Try a fresh teleport with the *same* endpoint and saved port (target IP can be set in Settings → Tunnel). Check Apple Maps independently. If no paired handshake works, do not assume changing the target IP will fix it.
6. Do not share/export the RPPairing file; it contains device pairing credentials. Retain a private copy of the full report for analysis.

## Interpretation

- **Service port different from 49152:** A wrongly assumed port can cause errors unrelated to cellular. iOS advertises Remote Pairing services via Bonjour, but discovery is not guaranteed in every state.
- **Loopback TCP connected** alone does **not** prove RPPairing, developer tunnel or GPS injection works. Compare the *paired handshake* result.
- **VPN 10.7.0.1 unavailable only on cellular:** Consistent with a LocalDevVPN routing or iOS local-device transport limitation, which Roam cannot fix by changing UI options alone.
- **RSD connected and fresh teleport works:** Report the exact network state and endpoint; then we can test repeatability without Wi-Fi.

## Preserved features

The location simulation engine, existing session reuse and cleanup, background cruise timer and counters, map scrolling/minimise, mph speed display and current iOS background-task behaviour are unchanged. Only diagnostic/Settings screens, report labels, version settings and the accompanying instructions have been modified.

## Build

Use your established GitHub Desktop → Codemagic → iLoader workflow. Create branch `roam-v0.22`, commit the extracted full-source project, push, select `roam-ios-unsigned`, download the resulting IPA and sign/install with iLoader.

If compilation fails, capture the **first Swift `error:`** in Codemagic's `Build iPhone Release app without code signing` step, rather than the final `xcodebuild` exit 65.
