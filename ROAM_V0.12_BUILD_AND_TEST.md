# Roam v0.12 — VPN visibility and staged cellular diagnostics

**Deliverable:** Complete, editable iPhone source project. **Build status:** Swift files parsed on Linux, config/structure checks passed. Not compiled with Apple's iOS SDK or tested on an iPhone in this environment. There is no prebuilt v0.12 IPA here.

## What changed from the supplied v0.11 source

1. **More accurate VPN interface *candidate* detection.** Roam now recognises the observed `utun` client IPv4 address `10.7.1.1`, as well as a target subnet match. It requires an active `utun` interface instead of looking for only `10.7.0.*`. This is *not* an authenticated check that LocalDevVPN owns the interface, and does not establish developer-service access. The banner and Settings deliberately say "VPN-like interface" / "candidate".
2. **Do not conflate the two addresses.** `10.7.1.1` was observed on the iPhone tunnel interface. `10.7.0.1` remains the default developer-service endpoint. The pairing and location engines keep targeting the endpoint unless the user changes Settings.
3. **Comparable TCP tests.** The interface-bound comparison now has an explicit destination picker (`10.7.0.1` or `127.0.0.1`). Both BSD probes use the same selected destination and port; the report identifies that host/port/interface. The ordinary Network.framework reachability test remains separate.
4. **Stage-specific paired-handshake results.** Roam records whether failure happened in pairing-file read, RPPairing tunnel creation, or RemoteXPC/RSD connection. The export includes the last attempted endpoint, port, stage, result and time. A TCP success alone is *not* paired-handshake success.
5. **More specific location-engine failure context.** The engine now retains sanitized `idevice` error codes/messages in its existing Settings diagnostic fields, not just a generic stage name. It does not export pairing credentials, and does not print GPS coordinates to the diagnostic report.
6. **v0.11 persistent-session teleport experiment preserved unchanged.** If a working session exists, Re-teleport still tries the retained handle and never implicitly stops it. The explicit End simulation confirmation remains.
7. **Build metadata** changed to 0.12.0 (12). Codemagic's `roam-ios-unsigned` workflow now verifies 0.12.0 / 12 and packages an **unsigned** `roam-v0.12-unsigned.ipa` for later signing.

## What this version does NOT establish

- It does not authenticate LocalDevVPN's ownership of a `utun` interface.
- It does not make `10.7.0.1` reachable automatically, modify VPN routes, or bind the `idevice`/RSD engine to a selected interface.
- It does not bypass Apple's developer-pairing security or iOS entitlements.
- It does not demonstrate fresh GPS teleportation over cellular-only connectivity.
- The provided IPA from the earlier upload is v0.10; do not label it a v0.12 build.

## Windows → GitHub Desktop → Codemagic

1. Keep the working Roam v0.9 installation, the original LocalDevVPN app, the current v0.10 experimental IPA and a secure copy of your RPPairing file. Do **not** commit or upload the pairing file, Apple credentials or provisioning/signing files.
2. In **GitHub Desktop**, open your Roam repository. **Create a branch named `roam-v0.12` from the newest working source branch** (prefer v0.11 if it exists). Do not overwrite `roam-v0.9` or the existing baseline branch.
3. Unzip the **full v0.12 source** and copy its contents into the local Roam repository, replacing the corresponding source/configuration files, including `Locus`, `Locus.xcodeproj`, `project.yml`, `codemagic.yaml` and `Vendor` if absent. The bundle ID is `com.roam.beanywhere.cellularresearch`, the same experimental ID used for v0.10/v0.11. Do not regenerate the `.xcodeproj` unless needed.
4. Review changes in GitHub Desktop, commit them to `roam-v0.12`, then **Publish branch**.
5. In Codemagic, choose branch `roam-v0.12`, workflow `roam-ios-unsigned`, and build. If it fails, copy the **first actual Swift or linker error** from `roam-build.log`; do not change random entitlements.
6. Download `roam-v0.12-unsigned.ipa` from build artifacts. It **must be signed** using your existing iLoader/sideloading workflow before the iPhone can run it. The file in this archive is source only; the IPA appears *after* a successful Codemagic build.
7. Some signers change the bundle ID. That can create a separate sandbox or replace the earlier experimental installation and may require importing the pairing file again. Verify the installed version in Roam Settings reads **0.12.0 (12)** before testing.

## Controlled tests on iPhone 17 Pro

1. Leave all active spoofing sessions stopped for read-only network diagnostics. Verify LocalDevVPN's status in **iOS Settings → VPN** first; Roam's candidate label does not verify it.
2. Turn **Wi-Fi OFF**, **Mobile Data ON**, leave LocalDevVPN connected, then open Roam → Settings → **Wi-Fi / 5G tunnel diagnostics** → **Cellular research** → **Refresh network snapshot**. Record the network path and `utun` client interface, especially `10.7.1.1` if present.
3. Set test port to **49152** unless your Roam Settings explicitly use another port. Tap **Run all three TCP tests**. Note results separately for `10.7.0.1`, `127.0.0.1`, and `::1`. These test TCP only.
4. Select the **utun with `10.7.1.1`** (if present), set **TCP target = VPN endpoint 10.7.0.1**, then press **Compare default vs interface-bound TCP**. Record both results. Optionally repeat with **Loopback 127.0.0.1**, remembering that binding loopback to a utun may be disallowed.
5. Only with **no active spoofing session**, try **Attempt paired handshake** at 10.7.0.1, then 127.0.0.1. Record the **Handshake stage** and exact **result**. Do not mistake "TCP connected" for authentication.
6. Press **Copy diagnostic report** and share the text after checking it for private identifiers or paths. No GPS coordinates or pairing file contents are intentionally included.
7. **Separate retained-session test, only if initial GPS works over Wi-Fi:** start a teleport on Wi-Fi and verify in Apple Maps; switch Wi-Fi OFF with Mobile Data ON **without pressing End simulation**. Choose a second destination, tap **Re-teleport**, verify in Apple Maps. Pause movement rather than ending the session between destinations. Use **End simulation** only when finished.

## Troubleshooting interpretation

- `127.0.0.1 TCP connected`: Some local socket accepts connections at that port; it does **not** establish that Apple RSD has paired successfully.
- `10.7.0.1 timed out`: That target/port did not complete TCP in the test window; check routes, endpoint listener, and actual LocalDevVPN settings.
- `Connection reset by peer (54)`: A reset occurred, potentially because of service/protocol mismatch or connection teardown; not proof of pairing rejection.
- `device socket io failed` during RPPairing: The tunnel establishment stage failed; do not infer GPS is responsible.
- `VPN candidate seen`: An interface resembles the expected tunnel; it is not cryptographic authentication or proof the extension is carrying the desired traffic.

**Privacy note:** Roam does not upload its report. Diagnostic error messages may contain local IPs, technical paths or device identifiers, so review before sharing. Keep unshared any possibly patentable findings pending professional IP advice.
