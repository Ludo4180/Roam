# Roam v0.18 — Extended Background Cruise Research

Built from the experimentally successful v0.17 source. **20s, 30s, and 60s** user-selected trials share the already-tested location-update path. Each trial requests one finite iOS background task; iOS may suspend or expire it early. No unconditional background modes or indefinite-execution claims.

The original 20s standard foreground cruise, Wi-Fi initial teleport, retained cellular teleport, diagnostics and LocalDevVPN handling are preserved in source, but this new build has **not** yet been compiled by Codemagic or tested on iPhone.

Version: **0.18.0 (18)**. Workflow: `roam-ios-unsigned`. Output: `roam-v0.18-unsigned.ipa`.

See [ROAM_V0.18_BUILD_AND_TEST.md](ROAM_V0.18_BUILD_AND_TEST.md).
