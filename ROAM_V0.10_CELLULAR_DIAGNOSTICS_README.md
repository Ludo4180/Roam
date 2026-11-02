# Roam v0.10 — cellular route isolation (experimental source)

**Status:** Source prepared from the v0.9 ZIP supplied by the user. Not compiled or device-tested by ChatGPT. **This is not a demonstrated 5G fix.**

## Evidence motivating this build

Using the *original* LocalDevVPN, paired RSD handshake at `10.7.0.1:49152` succeeded with Wi-Fi ON, and also with Wi-Fi OFF / mobile data OFF. Enabling mobile data with Wi-Fi OFF caused the handshake to fail; turning mobile data OFF restored success (OFF → ON → OFF). This is consistent with, but does not prove, a cellular network-routing or service-policy interaction. The VPN reporting Connected does not prove traffic reaches the packet tunnel.

## Changes versus v0.9

- Separate **INTERFACE-BOUND TCP** test in Settings → Wi-Fi / 5G tunnel diagnostics → Cellular research.
- Enumerates IPv4 addresses and `utun*` interface names/indexes and shows Network.framework path interface names.
- Highlights the `utun*` interface with `10.7.1.1` if visible; does **not** assert it belongs to LocalDevVPN. Other installed VPNs may also create `utun` interfaces.
- Compares ordinary BSD TCP socket with the same BSD TCP connection using Darwin `IP_BOUND_IF` (socket option 25) on the selected utun interface, TCP `10.7.0.1:49152`. Five-second timeout per test, errno on failure.
- Exports both comparison results in **Copy diagnostic report**. Pairing file and GPS coordinates are never included.
- New first-run **Open cellular diagnostics (no pairing needed)** button for the separate experimental app sandbox. The TCP diagnostics require no RPPairing file.
- App version and build labels updated to v0.10.0 (10).

## Important limitations

- A successful interface-bound **TCP** probe does not prove that Apple's paired developer protocol or location simulation works. This build does not inject or force a new interface into the precompiled idevice/RSD FFI socket. **We have not fixed cellular teleportation.**
- iOS can reject binding to a utun interface or route the connection differently than expected. Permission or route errors are diagnostic. The available interfaces list from `NWPathMonitor` may be different from `getifaddrs`; that itself may be a clue.
- `LocalDevVPN.isConnected` elsewhere in the app may incorrectly report Not detected because the VPN's local IP is `10.7.1.1`, while the checker expects `10.7.0.*`. The research screen shows the actual interface address instead.
- Existing Roam v0.9 source must be preserved separately. This project uses a distinct bundle ID (`com.roam.beanywhere.cellularresearch`), so its app sandbox will **not** automatically contain the v0.9 RPPairing file; reimport that file securely in the new build if a paired handshake is needed. **Never publish the pairing file.**
- Codemagic may require a build/signing workflow review; the source ZIP is not an IPA. iLoader may change bundle identifiers during signing.

## Controlled on-device test (no teleport or joystick needed)

1. With your ORIGINAL working LocalDevVPN connected, turn Wi-Fi OFF and mobile data OFF. Open Roam v0.10 → Cellular research → Refresh snapshot. Find the utun with `10.7.1.1` (commonly `utun4`, but not guaranteed).
2. Select the matching utun and tap **Compare default vs interface-bound TCP**. Copy report.
3. Without restarting or reconnecting LocalDevVPN, turn mobile data ON while leaving Wi-Fi OFF. Refresh snapshot, check selected utun, and repeat comparison. Copy report.
4. Do **not** assume that a TCP success means RSD will succeed. If this route probe is promising, further source and entitlement investigation is required before modifying the idevice FFI socket connection.

## Source files changed

- `Locus/Features/Settings/CellularResearchView.swift` — interface and socket diagnostics only.
- `Locus/Features/Settings/SettingsView.swift` — research section label.
- `Locus.xcodeproj/project.pbxproj` and `project.yml` — display version/build, distinct experimental bundle ID.
- `Locus/Resources/Info.plist` and `Locus/Support/LocalDevVPN.swift` — separate `roamdiagnostics://` URL scheme to avoid conflict with your existing v0.9 `roam://` callback.
- `Locus/Features/Setup/SetupFlowView.swift` — show read-only cellular diagnostics without the pairing setup on a fresh installation.
- `codemagic.yaml` — workflow label only.

Build/test on Codemagic in a separate branch/repository. The existing application and working baseline need not be replaced.
