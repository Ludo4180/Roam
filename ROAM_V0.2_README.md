# Roam v0.2 - GPS engine integration build candidate

This is a SOURCE project for a native iPhone app, NOT an installable IPA yet.
It derives from ChrisMack32/Locus (MIT) and retains its full LICENSE and Vendor/idevice files.
The original Locus installation on your iPhone is unaffected.

Working directory:
  C:\Users\simon\Develop\Roam\Roam_v0.2_iOS

Roam v0.1 UI is separately backed up; this engine-first branch uses Locus's proven
location features (teleport, joystick, routing, pairing, LocalDevVPN) with an initial
Roam brand pass. We will merge the earlier UI refinements after an iPhone build.

IMPORTANT:
- We cannot compile or validate this native iOS project on Windows.
- Requires Mac, Xcode, signing and possibly XcodeGen to generate/update project.
- The internal Xcode target/scheme and folder remain named Locus for now.
- The old Locus app icon may remain until Roam's app icon is integrated.
- Roam has its own bundle identifier and app sandbox. It may require its own
  on-device developer pairing on your iPhone; Locus's pairing isn't shared.
- New teleports over cellular have NOT been shown to work. First use Wi-Fi.
- LocationEngine/SpoofSession are unchanged to avoid breaking the working engine.

When a Mac is available:
  1. Copy this entire Roam_v0.2_iOS directory to the Mac.
  2. Install Xcode and XcodeGen (brew install xcodegen).
  3. In Terminal: cd into Roam_v0.2_iOS; run 'xcodegen generate'.
  4. Open Locus.xcodeproj, choose the Locus scheme and your Apple signing team.
  5. Build to your own iPhone; test pairing, Wi-Fi teleport, then 5G joystick.

Do NOT remove or overwrite your working Locus iPhone installation.
Licence and upstream documentation are retained in this folder.