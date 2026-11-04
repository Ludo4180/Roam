# Roam v0.16 — Codemagic Step 4 hotfix (v0.16.1 packaging revision)

The app source remains **Roam v0.16.0 (build 16)**. This hotfix only updates the Codemagic build workflow and XcodeGen fallback version values. It does NOT alter the GPS engine, movement recovery, pairing, VPN, or joystick code.

## Why Step 4 failed
The original `codemagic.yaml` was accidentally left with the version checks `0.15.0` and `15` even though the Xcode project generated `0.16.0` / `16`. Therefore a successful compile would fail the post-build version gate. Step 4 ran `set -eu` and exited at the mismatched `test` check. Step 5 packaging was never reached.

## Corrected values
- Expected app version: **0.16.0**
- Expected app build: **16**
- Output IPA: **roam-v0.16-unsigned.ipa**
- Workflow label: **Roam v0.16**
- `project.yml` fallback (if XcodeGen is ever used): **0.16.0 (16)**

## Install the fix on your current GitHub branch
1. Leave existing Swift files, VPN code, and `Locus.xcodeproj` untouched.
2. Extract the patch. Copy `codemagic.yaml` to the repository root, replacing the old file. You may also replace `project.yml` for consistency.
3. Commit and push to your current `roam-v0.16` branch.
4. Rerun workflow `roam-ios-unsigned` in Codemagic.
5. On success, download `roam-v0.16-unsigned.ipa` from Artifacts and install with the previously used iLoader process.

**Note:** No Xcode/iOS SDK compile was possible here; the user's successful Step 3 is the compilation evidence. This package fixes the verified version mismatch, but any other error will require its full log.
