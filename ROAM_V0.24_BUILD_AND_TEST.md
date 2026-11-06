# ROAM – BE ANYWHERE — v0.24 build and iPhone test

## Scope

This release adds only a guided **Wi-Fi-free startup workflow** to the existing v0.23 application UI. It does **not** alter `LocationEngine.swift`, `SpoofSession.swift`, pairing, GPS/background movement, or original LocalDevVPN. The confirmed technique requires **LocalDevVPN to be connected before turning mobile data off**. It does not prove the VPN can establish its own new connection with cellular continuously enabled.

## What's added

- Settings → **Wi-Fi-free startup** guide; accessible via the lightning icon on compact map controls and via expanded controls.
- Live `NWPathMonitor` result, imported pairing-file status, unverified VPN interface candidate, retained GPS handle and engine stage/error.
- Start or Re-teleport at the **currently selected map pin** without clearing an existing GPS session.
- Failure guidance that avoids resetting an active session.
- Optional advice to create two Shortcuts with **Set Cellular Data → Off/On** (if the native action is available on the iPhone). The application does not run Shortcuts or change radios itself.

## Codemagic (Windows workflow)

1. Back up the functioning v0.23 source and installed IPA. In GitHub Desktop, create a new branch `roam-v0.24`.
2. Extract the **complete v0.24 source ZIP** into the root of your Roam repository (the directory with `Locus.xcodeproj` and `codemagic.yaml`). Replace v0.23 source files.
3. Commit and push, open Codemagic and run **`roam-ios-unsigned`**.
4. Verify the version stage reports **0.24.0 (24)** and the unsigned artifact is **`roam-v0.24-unsigned.ipa`**.
5. Download the IPA and use the same iLoader signing/install workflow that succeeded for v0.23. Signing/provisioning remains dependent on the user's setup; an unsigned IPA is not directly installable.

Alternative: use the PATCH ZIP to overlay only changed files onto an unchanged v0.23 repository.

## Device tests (in order)

### A. First check the new screen

1. Open Roam and expand the controls. Tap **Wi-Fi-free startup guide**.
2. Confirm it displays the imported pairing file and network-path label; VPN interface is explicitly labelled a **candidate**.
3. Dismiss the guide. Minimise the controls, tap the lightning shortcut and confirm the guide opens again.
4. Confirm existing map/joystick controls and speed units in mph still work.

### B. Fresh Wi-Fi-free startup

1. Stop any previous Roam simulation **only when you're ready to create a new one**. Never stop a working session just to view diagnostics.
2. With Wi-Fi OFF and mobile data ON, connect original LocalDevVPN and verify its VPN status under iPhone Settings.
3. In Settings, switch mobile data OFF while leaving Wi-Fi OFF. Keep LocalDevVPN connected. The guide should show a network-path change, usually *No usable uplink reported*; this indicator is not itself proof both radios are off.
4. Return to Roam. Tap a new map destination. Open the guide and press **Start teleport at selected pin** (or use the normal map Teleport).
5. Check Apple Maps mirrors the simulated GPS position. Turn mobile data ON, keep Wi-Fi OFF, and verify Apple Maps still mirrors. Re-teleport to a second destination.

### C. Recovery and regression

- With cellular left ON, a new pairing connection may still fail with code 61. The guide should not silently retry, reset LocalDevVPN or discard the pairing file.
- Existing developer session should remain usable when closing the guide or switching apps.
- Recheck a brief 20-second background movement experiment after the interface checks. The code is unchanged, but a real device test confirms no regression.

## Safety and limits

- Never publish your RPPairing file or developer credentials.
- A UI showing an active session is not independent verification; Apple Maps is the verification step.
- The iOS app cannot use public APIs to silently toggle mobile data. Users must use Settings or their own Shortcuts.
- `swiftc -frontend -parse` can verify Swift syntax on Linux, not Xcode/UIKit module typechecking or an iOS build. Codemagic is the actual compiler check.
