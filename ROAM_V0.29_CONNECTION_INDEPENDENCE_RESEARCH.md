# Roam v0.29 — LocalDevVPN independence research

**Research status:** no validated replacement for the installed LocalDevVPN has been implemented in this release. The aim is to identify an independent connection architecture without jeopardising the fully tested v0.28/v0.29 engine.

## What has actually been demonstrated on the iPhone

- A fresh paired developer/RSD handshake can complete in ~0.2s when **Wi-Fi OFF and cellular OFF**, provided LocalDevVPN's virtual interface is already connected.
- A fresh offline teleport, Apple Maps mirroring, re-teleportation after turning cellular ON, and five-minute observed simulated movement all worked in the subsequent versions.
- The `Roam Cold Start` Shortcut can use Apple's **Set VPN** action to connect the installed LocalDevVPN profile when it was previously disconnected, then turn off cellular and return to Roam. This removes the *manual VPN connection step*, not the app dependency.
- When cellular is initially ON, the developer endpoint `10.7.0.1:49152` was refused over the normal and VPN-bound routes in earlier diagnostic builds. The short offline period is the current proven workaround.

## Options, trade-offs and constraints

| Architecture | Current assessment | Why not integrated in v0.29 |
| --- | --- | --- |
| **LocalDevVPN via Shortcuts** | Demonstrated and retained | This is the user-tested baseline. Keep it. |
| **Packet tunnel extension embedded inside Roam** | Technically possible to prototype in a separate signed app, but needs `packet-tunnel-provider` entitlement/provisioning | Apple's Network Extension entitlement is required; an unsigned build or ordinary free-team provisioning cannot be assumed to run it. Changes risk breaking the current workflow. |
| **Connect directly to a link-local / alternate interface** | Previous reports found TCP listeners on other local interfaces; no authenticated, GPS-working session proven on this device | A TCP connection is not a paired RSD handshake. Routing and interface ownership are unverified. Do not guess IPs or replace stable target settings. |
| **Use ordinary Core Location to simulate device-wide GPS** | No public system-wide spoofing API exposed by ordinary Core Location | Core Location provides position observation, not privileged developer-service location injection. |
| **External Mac/PC bridge or hardware** | Potentially a different transport but not the requested independent iPhone-only solution | Would violate the user's requirement for no external device during everyday usage. |

## Recommended next isolated engineering experiment

If the user wishes to pursue complete independence, use a **separate read-only diagnostic build or a fully signed extension prototype**. First determine whether the paired RSD developer service is reachable on a non-VPN local transport after a cold cellular start. Demand both authenticated handshake and Apple Maps-confirmed teleport before calling any candidate a replacement. Do not overwrite the known-working Roam source or ship a new VPN extension without the needed entitlements, provisioning and rollback strategy.

## Public references

- Apple, `NEPacketTunnelProvider`: https://developer.apple.com/documentation/NetworkExtension/NEPacketTunnelProvider
- Apple, Network Extensions entitlement: https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.developer.networking.networkextension
- Apple, Core Location overview: https://developer.apple.com/documentation/corelocation
- LocalDevVPN issue #31, cellular tunnel limitation: https://github.com/jkcoxson/LocalDevVPN/issues/31

**IP/privacy:** Avoid posting any novel approach or pairing details publicly before a dedicated IP review. Diagnostics should omit device identifiers, pairing credentials and location coordinates.
