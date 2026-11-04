# Roam v0.17 — controlled 20-second background cruise experiment

**Base:** The previously successful v0.16.1 corrected Codemagic source.
**App build metadata:** 0.17.0 (17).
**iOS output:** `roam-v0.17-unsigned.ipa` from workflow `roam-ios-unsigned`.

## Scope of this experimental build

- Keeps the existing **Move north for 20s** control: foreground cruise, intentional pause on background, and resume on return.
- Adds **Try 20s background cruise (experimental)** as a separate opt-in button; a background task is requested **before** starting the trial, and ended when the trial completes, is stopped, errors, or expires.
- The experimental trial attempts to continue sending the *same existing location-simulation API updates* after Roam changes to background state. No new pairing method, developer endpoint, or unrestricted background mode is claimed.
- Records scene background transitions; API attempts/acceptances/failures **during the background state**; requested metres accepted by the API; task expiry and last attempted background command.
- Does not send an artificial accumulated movement jump for the time the app is suspended.
- Keeps an existing retained location session rather than calling clear/stop on application handover.
- Removes the old generic background-task assertion from every teleport. Only the finite, explicit experimental cruise requests UIKit background task time.
- Does **not** add location/audio/VoIP background modes or promise indefinite execution.

Apple's `UIApplication.beginBackgroundTask` requests *finite additional execution time*, not a guarantee; the app may be suspended or the request may expire or fail. Every successful request is balanced by `endBackgroundTask`.

## Building on Windows

1. **Back up the working v0.16 project and IPA.**
2. In GitHub Desktop create a new branch, e.g. `roam-v0.17`.
3. Extract the **full-source ZIP** into the repository root and replace existing files (do not nest it inside an extra folder). Alternatively extract the upgrade patch into the v0.16.1 source root, keeping the relative file paths.
4. Commit and push.
5. In Codemagic select workflow `roam-ios-unsigned` on the new branch.
6. Download `roam-v0.17-unsigned.ipa` from Artifacts after the build and verification steps pass, and sign/install using the established iLoader procedure.

The source has been Swift **syntax parsed** locally and versions checked in `project.yml`, `Locus.xcodeproj/project.pbxproj`, and `codemagic.yaml`. No Apple iOS SDK build or on-device validation has been performed here. If Codemagic fails, retrieve the *first* Swift `error:` line or the failed verification step.

## Test on iPhone (20 seconds)

1. Preserve the v0.16 baseline. On v0.17, verify normal teleport over Wi-Fi and a **re-teleport over cellular with Wi-Fi completely off** in Settings, while keeping the existing LocalDevVPN/developer session.
2. With that session active, Wi-Fi OFF, mobile data ON, choose **Drive**.
3. Tap **Try 20s background cruise (experimental)**, not the older **Move north for 20s**.
4. After around 3 seconds switch to Apple Maps and keep Apple Maps in front for about 15–20 seconds. Do not press End Simulation or end the VPN.
5. See whether the Apple Maps blue dot *visibly moves live* or remains at its last position. Do not assume the API result proves Apple Maps movement.
6. Return to Roam; open **GPS movement diagnostics → Experimental background cruise (v0.17)**. Note background commands attempted / accepted / failed, task expiry, and lifecycle lines. Copy the full diagnostic report if convenient; it contains coordinates, so review before sharing.

**Interpreting results:**

- **Background accepted commands > 0:** The app attempted commands while it reported background scene status and the API returned success. Only a visually changing Apple Maps dot confirms that map received those updates.
- **0 background commands, no expiration:** iOS may have suspended the timer/operation or it may never have entered background during the trial. Check lifecycle timestamps.
- **Task expired:** UIKit ended the finite background allowance; the trial stops and may resume its *remaining* duration upon returning foreground if a session is still present.
- **Background API failed:** The developer connection may be unusable while backgrounded; check the last failure and retained session state.

This experiment does not solve standalone 4G/5G *initial* developer connection or guarantee background operation beyond this trial.
