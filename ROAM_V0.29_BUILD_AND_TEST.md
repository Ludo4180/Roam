# Roam v0.29 — Build, installation & regression guide

**Starting point:** the fully tested v0.28 source / installed IPA. **Branch:** `roam-v0.29`. **Expected Codemagic artifact:** `roam-v0.29-unsigned.ipa`.

## Install from Windows via GitHub and Codemagic

1. Back up the **working v0.28 ZIP/source and IPA**. Do not uninstall the working app or alter LocalDevVPN.
2. In GitHub Desktop create `roam-v0.29` from the v0.28 revision.
3. Extract `Roam_v0.29_FULL_SOURCE.zip` **into the root of the existing Roam repository**, allowing replacement of tracked project files but retaining `.git`. Alternatively apply `Roam_v0.29_PATCH_FROM_v0.28.zip` to an *exact* v0.28 source checkout.
4. Commit and push, run Codemagic workflow `roam-ios-unsigned` on the correct branch. The built app MUST report **0.29.0 (29)**. The verification script checks these values rather than the previous 0.28 build number.
5. Download `roam-v0.29-unsigned.ipa` and sign/install through the **existing working iLoader procedure**. This archive is unsigned source; installation requires the same provisioning path that previously worked for you.
6. With multiple Roam versions on the iPhone, open **each** existing Shortcut and change `Open App` to **Roam v0.29**. Do not select an older Roam icon.

## Keep these exact Shortcut names

- `Roam Cold Start`: **Set VPN → Connect LocalDevVPN** → **Wait 5 seconds** → **Set Cellular Data OFF** → **Open App Roam v0.29**.
- `Roam Data Off`: **Set Cellular Data OFF** → **Open App Roam v0.29**.
- `Roam Data On`: **Set Cellular Data ON** → **Open App Roam v0.29**.

Roam only invokes these **user-created** Shortcuts. It never directly changes cellular data or the VPN configuration.

## Device validation checklist (in order)

1. **Visual & basic safety.** Open v0.29. From the map, tap the four-square icon in compact controls or **Command Centre** in expanded controls. Confirm the main panel opens and closes, shows your pairing-file status, and does **not** claim an observed `utun` is authenticated. Ensure selecting/dismissing it does not end a GPS session.
2. **Cold Start.** Stop any existing simulation deliberately, turn Wi-Fi OFF, mobile data ON; disconnect the installed LocalDevVPN VPN **without removing its profile**. Choose a destination. Open **Cold Start / Wi-Fi-free setup** from Command Centre. Run the existing `Roam Cold Start` flow. It should connect the VPN, briefly turn cellular OFF, return to v0.29 and send one GPS teleport when its route checks pass.
3. **Independent location check.** Open Apple Maps and confirm the blue dot at the selected destination. A green Roam status / API acceptance does not replace this observation.
4. **Restore & re-teleport.** Use `Roam Data On` to restore mobile data with Wi-Fi still OFF, choose a second destination, then use **Re-teleport** in Command Centre. Verify Apple Maps follows.
5. **Movement commands.** From an active session, test the new **20-second cruise** button and then the **5-minute cruise** option (confirmation required). Observe actual blue-dot movement in Apple Maps when Roam is backgrounded. Note if the background task expires before the requested duration.
6. **Stop movement vs stop GPS.** `Stop movement` and `Pause movement` must not clear the last simulated coordinate. **End GPS Session** must request explicit confirmation before it clears the simulation. Only use the latter when you truly want to stop spoofing.
7. **Recovery.** Verify **Startup & Data On** opens the same proven guide, and that **Open LocalDevVPN** does not change pairing data. Try a cancelled guide without deleting or resetting any credentials.
8. **Privacy & diagnostics.** In Command Centre use **Copy safe summary**. Verify it contains no destination coordinates, tunnel IPs, secret pairing contents, or personal identifiers. Do not share raw pairing files.
9. **Repeated runs.** Repeat three *fresh*, disconnected-VPN Cold Starts on separate attempts, noting any failed Shortcuts or delayed returns. If failures occur, retain v0.28 and the safe summary for diagnosis.

## Expected limitations

- The LocalDevVPN **installation is still required**; its manual connection is automated by Shortcuts. The separate connection research is documented in `ROAM_V0.29_CONNECTION_INDEPENDENCE_RESEARCH.md`.
- Fresh pairing direct over cellular with the VPN completely absent is **not** proven. `NWPathMonitor` and `utun` observations cannot verify tunnel ownership or authentication.
- The 5-minute cruise is a finite experimental request that may end early; observing live movement in Apple Maps is a stronger independent check than API acknowledgements.
- Swift syntax parsing on Linux cannot replace Xcode type checking or real signed-device testing. If Codemagic fails, send the **first compiler error**, not only the final summary line.
