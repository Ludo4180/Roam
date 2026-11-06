# Roam v0.23 — Cellular Route A/B Investigation

## Purpose

This is a **non-destructive diagnostic build** based on v0.22. It preserves the existing GPS teleportation, retained 4G/5G session, background cruise engine, minimisable map controls, and mph presets.

Prior testing established:

- **Wi-Fi:** `10.7.0.1:49152` connected and paired RSD handshake succeeded.
- **Cellular:** Same endpoint failed TCP with `ECONNREFUSED (61)`; paired tunnel failed (`16/0`).
- **Loopback `127.0.0.1:49152`:** TCP connected but pairing reset (`54`) on both transports.
- Bonjour advertised port **49152** on Wi-Fi. That makes a simple wrong-port explanation less likely.

The remaining question is **what each network path and interface-bound TCP test can see**, not whether the GPS movement algorithm works.

## Changes in v0.23

Open **Roam → Settings → 5G startup / route audit → v0.23 CELLULAR ROUTE COMPARISON**. New read-only tests:

- Ordinary TCP connection to `10.7.0.1` on the saved pairing port.
- Interface-bound TCP connection to the candidate `utun` address associated with `10.7.1.1` (when visible).
- Interface-bound TCP connection using `en0` for Wi-Fi or `pdp_ip0` for cellular (both candidates, not guarantees).
- Ordinary loopback TCP control to `127.0.0.1`.
- Network.framework connection path status for `10.7.0.1` and, when connected, the socket's numeric local source address.
- Saves separate Wi-Fi and cellular snapshots in on-device UserDefaults, for comparison after changing network.
- Includes findings in **Copy diagnostic report**.

**No route change, VPN restart, pairing modification, GPS command or automatic bypass is attempted.** This test is disabled while a GPS simulation is active. It cannot inspect another app's packet tunnel logs/counters, routing configuration or kernel route table. Seeing a `utun` interface doesn't prove it belongs to LocalDevVPN.

## Build in Codemagic

1. Back up the working Roam v0.22 source and IPA.
2. Create and publish GitHub branch `roam-v0.23`.
3. Extract `Roam_v0.23_FULL_SOURCE.zip` into the repository root, overwriting the previous source (or apply the v0.22 → v0.23 patch).
4. Commit and push.
5. Run the `roam-ios-unsigned` Codemagic workflow.
6. Download `roam-v0.23-unsigned.ipa`, install through iLoader as usual.
7. Check Settings → About Roam shows **0.23.0 (23)**.

## Test A — Wi-Fi baseline

1. With **no active simulation**, enable Wi-Fi in iPhone Settings and connect to your normal network.
2. Confirm LocalDevVPN shows connected in iOS Settings. Do not alter its configuration.
3. Open **Roam → Settings → 5G startup / route audit**.
4. In **v0.23 CELLULAR ROUTE COMPARISON**, tap **Capture this network's route audit**.
5. Verify a **Saved Wi-Fi baseline** appears. The VPN-pairing test from v0.22 is still available separately but is not part of this capture.

## Test B — Cellular baseline

1. Stop any active simulation.
2. Turn **Wi-Fi OFF in the iPhone Settings app** (not just Control Centre); keep cellular data on.
3. Verify LocalDevVPN shows connected (even if unusable), without changing or resetting its settings.
4. Return to the same v0.23 route-comparison section.
5. Tap **Capture this network's route audit** again.
6. Check that both **Saved Wi-Fi baseline** and **Saved cellular baseline** are displayed.
7. Scroll to **Copy diagnostic report** and send the text or screenshots for comparison.

## Reading the results

- **`TCP connected`:** confirms a socket connected; does not authenticate the Apple developer protocol. The local IP is the source address of that *one successful socket*, not evidence for other apps' traffic.
- **`Connection refused (errno 61)`:** target socket refused; could be no listener at that route, unsupported tunnel delivery, or another network restriction.
- **`Connection reset (errno 54)`:** something accepted TCP then closed it, but did not complete the remote pairing protocol.
- **`IP_BOUND_IF failed`:** iOS declined that interface binding; does not prove the route cannot exist.
- **`Timed out`:** no usable reply within five seconds.
- **`NWPath uses / available`:** Network.framework observation, **not** the kernel route table or packet provenance.

## Important

The LocalDevVPN project maintainers publicly report cellular-only limitations. This build **does not solve or claim to bypass them**. It helps identify whether the failure is visible at TCP routing/interface-selection level. Keep v0.22 backed up as the last independently tested version until v0.23 is verified on device.

## Validation

The source is checked with a Linux Swift syntax parser and ZIP/archive checks. The actual iOS compilation requires Codemagic/Xcode, and actual route observations require your iPhone.
