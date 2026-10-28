# Roam v0.7 — minimal diagnostic rebuild

This is the COMPLETE Xcode project source tree, not a compiled IPA. It was created from the original v0.6 source (known to work on the user's phone).

Changes from v0.6 (only):
- Settings > Tunnel: add 'Test developer endpoint (TCP 49152)' and a result label. This is copied from the v0.7 diagnostic source that previously compiled successfully on Codemagic; it tests basic TCP reachability, not device pairing or GPS injection.
- Xcode project build settings: MARKETING_VERSION 0.7.0 and CURRENT_PROJECT_VERSION 7 in BOTH configurations.
- project.yml (if XcodeGen is used): corresponding version and build update.
- codemagic.yaml copied from previously successful Codemagic workflow, with its display name updated to v0.7. Same scheme, build commands, and unsigned signing setting.

Everything else — including LocationEngine, SpoofSession, VPN utility, pairing, app icon, embedded idevice library — remains byte-for-byte identical to the original v0.6 source.

## Windows > GitHub Desktop > Codemagic
1. KEEP a backup of your current `C:\Users\simon\Documents\GitHub\Roam` repo and of your working v0.6 IPA. Do not erase the repo's `.git` folder.
2. Extract this ZIP to a temporary folder, then copy its **contents** (not the outer folder) over the corresponding paths within the local GitHub Roam repo. The ZIP intentionally contains no `.git` folder.
3. Open GitHub Desktop. Verify changes are limited to SettingsView.swift, project.pbxproj, project.yml, codemagic.yaml plus this README. Commit and push; use your existing Codemagic workflow `roam-ios-unsigned`.
4. When Codemagic succeeds, download its `.app` artifact and package as `Payload/Roam.app` inside a ZIP renamed `.ipa` as before. Verify the extracted Roam.app/Info.plist's CFBundleShortVersionString is 0.7.0 and CFBundleVersion is 7. (It is only a confirmation if the build used this source.)
5. Import that unsigned IPA with iloader. Replacing installed v0.6 is optional; **do not uninstall Locus, revoke certificates or delete pairing**. Because the previous diagnostic couldn't launch, consider saving v0.6 IPA and pairing information before replacing it.
6. To test 4G/5G tunnel reachability: LocalDevVPN connected, Roam > Settings > Tunnel, tap 'Test developer endpoint (TCP 49152)' first with mobile data OFF, then with Wi-Fi OFF / mobile data ON, while keeping LocalDevVPN connected. Record the endpoint diagnostic message exactly.

Important: The TCP endpoint test does not directly prove GPS simulation will succeed. It is a diagnostic-only release, not a cellular fix. No claim is made that increasing the version number will fix verification. Codemagic and iPhone installation cannot be executed from this environment.
