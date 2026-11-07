import SwiftUI
import Network
import CoreLocation

/// v0.28: stability and interface refinement of the verified v0.27 Cold Start workflow.
/// A user-built Shortcut may first connect the EXISTING LocalDevVPN VPN profile,
/// then turn off cellular and return here. Only after offline route checks pass
/// will Roam send one GPS command. No VPN entitlement, silent network changes,
/// automatic re-pairing, or changes to the stable location engine.
struct OfflineStartupGuideView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var network = OfflineStartupNetworkObserver()
    @State private var vpnCandidateVisible = LocalDevVPN.tunnelCandidate != nil
    @State private var attemptedFromGuide = false
    @State private var showShortcutsHelp = false
    @State private var showAdvanced = false
    @State private var showColdStartHelp = false
    @State private var showReliabilityPlan = false
    @State private var summaryCopied = false
    @State private var recoverySuggested = false
    // User-entered Apple Maps confirmation, never inferred from API success.
    @State private var mapsVerificationPending = false
    @State private var mapsVerificationStatus = ""

    // v0.27 experimental path: LocalDevVPN was initially disconnected.
    // These flags never persist, so relaunching Roam cannot trigger a teleport.
    @State private var coldStartArmed = false
    @State private var coldProbeApproved = false
    @State private var coldProbeRunning = false
    @State private var coldProbeNextAttemptAt = Date.distantPast
    @State private var coldProbeGeneration = UUID()
    @State private var coldProbeFeedback = "Not attempted"
    @State private var lastColdStartSuccess = false

    // One-shot, *in-memory only* request. It is never restored after app launch.
    @State private var vpnCheckedByUser = false
    @State private var autoStartArmed = false
    @State private var leftAppAfterArming = false
    @State private var returnedAfterArming = false
    @State private var autoStartArmedAt: Date?
    @State private var autoStartPin: CLLocationCoordinate2D?
    @State private var oneTapFeedback = "Not started — create the two Shortcuts first"
    @State private var autoStartAcceptedLocally = false

    // v0.26: OFF by default every time the guide is opened. After explicit opt-in,
    // a successful one-shot API request can hand off to the USER-CREATED Data On Shortcut.
    // This is NOT a direct cellular setting change, and API acceptance does not prove
    // that Apple Maps has moved. The existing manual restore action always remains.
    @State private var autoRestoreForThisStart = false
    @State private var pendingRestoreHandoff: UUID?
    @State private var restoreRequested = false
    @State private var restoreLeftApp = false
    @State private var restoreReturnedToApp = false
    @State private var restoreFeedback = "No restore requested yet"
    @State private var cellularReturnRecorded = false

    // No location coordinates, pairing secrets or IPs are logged or persisted.
    @AppStorage("roam.v026.oneTapStarts") private var oneTapStarts = 0
    @AppStorage("roam.v026.oneTapAccepted") private var oneTapAccepted = 0
    @AppStorage("roam.v026.oneTapFailed") private var oneTapFailed = 0
    @AppStorage("roam.v026.restoreRequests") private var restoreRequests = 0
    @AppStorage("roam.v026.cellularPathReturns") private var cellularPathReturns = 0
    @AppStorage("roam.v027.coldStarts") private var coldStarts = 0
    @AppStorage("roam.v027.coldAccepted") private var coldAccepted = 0
    @AppStorage("roam.v027.coldFailures") private var coldFailures = 0
    @AppStorage("roam.v028.mapsConfirmed") private var mapsConfirmed = 0
    @AppStorage("roam.v028.mapsNotMatched") private var mapsNotMatched = 0
    private let autoStartTimeout: TimeInterval = 90

    private var canArmAutoStart: Bool {
        vpnCheckedByUser && pairing.hasPairingFile && session.pin != nil &&
        !session.isBusy && network.hasCheckedPath &&
        !network.wifiPathObserved && !network.offlineObserved && !autoStartArmed
    }

    private var canArmColdStart: Bool {
        pairing.hasPairingFile && session.pin != nil && !session.isBusy &&
        !session.isSpoofing && !autoStartArmed && network.hasCheckedPath &&
        network.cellularPathObserved && !network.wifiPathObserved
    }

    private var retainedHandle: Bool { LocationEngine.isSessionActive }

    private var startupPhaseTitle: String {
        if autoStartArmed { return coldStartArmed ? "Cold Start armed" : "One-Tap startup armed" }
        if pendingRestoreHandoff != nil { return "Restoring cellular shortly" }
        if autoStartAcceptedLocally && network.cellularPathObserved { return "GPS command accepted · cellular path detected" }
        if autoStartAcceptedLocally { return "GPS command accepted · verify Apple Maps" }
        if session.isSpoofing { return "Existing GPS session active" }
        if network.wifiPathObserved { return "Turn off Wi-Fi for Cold Start" }
        if network.offlineObserved { return "Offline · VPN route needed for fresh startup" }
        return "Ready for assisted startup"
    }

    private var startupPhaseDetail: String {
        if autoStartArmed { return "Return to Roam after the Shortcut finishes. No GPS command will be sent until the offline checks pass." }
        if autoStartAcceptedLocally { return "The local API response is not an Apple Maps verification. Retest independently before relying on it." }
        if session.isSpoofing { return "Preserve the working session; use Re-teleport rather than starting another Cold Start." }
        return "Select a map destination, keep Wi-Fi off, and use Cold Start to connect your installed LocalDevVPN automatically." 
    }

    private var startupStatusCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: autoStartArmed ? "clock.arrow.circlepath" : (autoStartAcceptedLocally ? "checkmark.circle.fill" : "bolt.horizontal.circle.fill"))
                .font(.system(size: 23))
                .foregroundStyle(RoamPalette.turquoise)
            VStack(alignment: .leading, spacing: 5) {
                Text(startupPhaseTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(startupPhaseDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(RoamPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .roamSurface(cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(RoamPalette.turquoise)
                            .frame(width: 44, height: 44)
                            .background(RoamPalette.turquoise.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Roam Quick Start")
                                .font(.system(size: 23, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("v0.28 · Cold Start & connection assistant")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(RoamPalette.muted)
                        }
                    }
                    Text("Cold Start now supports the working Wi-Fi-free procedure from v0.27. It uses your installed LocalDevVPN and the iPhone Shortcut; the proven VPN-already-connected option is still available.")
                        .font(.subheadline)
                        .foregroundStyle(RoamPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    startupStatusCard

                    VStack(alignment: .leading, spacing: 11) {
                        Text("LIVE CHECKS")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(RoamPalette.turquoise)
                        stateRow("Network path", network.pathDescription, symbol: "network")
                        stateRow("Pairing file", pairing.hasPairingFile ? "Available" : "Missing — import in Settings", symbol: "key.fill")
                        stateRow("VPN interface", vpnCandidateVisible ? "Candidate visible (not verified)" : "No candidate detected", symbol: "shield.lefthalf.filled")
                        stateRow("Developer GPS handle", retainedHandle ? "Retained on this launch" : "Not currently retained", symbol: "location.circle")
                        stateRow("Roam engine", session.status.label, symbol: "waveform.path.ecg")
                        Button {
                            refresh()
                        } label: {
                            Label("Refresh checks", systemImage: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        Text("The network path and VPN candidate are indicators, not proof that LocalDevVPN is connected. Confirm VPN in iPhone Settings; verify the result in Apple Maps.")
                            .font(.system(size: 11))
                            .foregroundStyle(RoamPalette.muted)
                    }
                    .padding(15)
                    .roamSurface(cornerRadius: 20)

                    coldStartCard
                    oneTapCard
                    if recoverySuggested { recoveryCard }
                    reliabilityPlanCard

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
                    } label: {
                        HStack {
                            Label("Diagnostics, statistics & manual steps", systemImage: "waveform.path.ecg")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                                .foregroundStyle(RoamPalette.turquoise)
                        }
                        .padding(15)
                        .roamSurface(cornerRadius: 16)
                    }
                    .buttonStyle(.plain)
                    if showAdvanced {
                      reliabilityCard

                    VStack(alignment: .leading, spacing: 12) {
                        step(1, title: "Connect LocalDevVPN", note: "With mobile data ON, connect the original LocalDevVPN manually or use the new Cold Start Shortcut. Confirm Settings → VPN says Connected. Do not replace the working VPN.")
                        step(2, title: "Temporarily go offline", note: "In iPhone Settings turn Wi-Fi OFF and Mobile Data OFF. Leave LocalDevVPN connected, then return to Roam.")
                        step(3, title: "Teleport while offline", note: "Select a location on Roam's map. Start Teleport below, or return to the map and use Teleport. Wait for the result.")
                        step(4, title: "Restore cellular", note: "When the teleport succeeds, turn Mobile Data ON again. Keep Wi-Fi OFF and confirm Apple Maps displays the simulated location. Re-teleport normally.")
                    }
                    .padding(15)
                    .roamSurface(cornerRadius: 20)

                    VStack(alignment: .leading, spacing: 11) {
                        Text("TELEPORT — MANUAL TEST")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(RoamPalette.turquoise)
                        if let destination = session.pin {
                            Text(String(format: "Selected map pin: %.5f, %.5f", destination.latitude, destination.longitude))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(RoamPalette.muted)
                        } else {
                            Text("No destination selected. Return to the map, tap a place, then reopen this guide.")
                                .font(.subheadline)
                                .foregroundStyle(RoamPalette.muted)
                        }
                        if !network.offlineObserved {
                            Label("The monitored network path is not offline. For a NEW session, use the proven mobile-data-OFF sequence before testing.", systemImage: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(LocusTheme.statusWarn)
                        } else {
                            Label("Offline path observed. Check both radio toggles manually.", systemImage: "checkmark.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(RoamPalette.turquoise)
                        }
                        Button {
                            guard let coordinate = session.pin else { return }
                            attemptedFromGuide = true
                            session.teleport(to: coordinate, pairing: pairing)
                        } label: {
                            Label(session.isSpoofing ? "Re-teleport selected pin" : "Start teleport at selected pin", systemImage: "location.north.fill")
                                .font(.system(size: 14, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(RoamPalette.turquoise)
                        .disabled(session.pin == nil || !pairing.hasPairingFile || session.isBusy)
                        if attemptedFromGuide || retainedHandle {
                            Text(session.lastTeleportResult)
                                .font(.system(size: 12))
                                .foregroundStyle(RoamPalette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let error = session.lastError {
                            Text("Most recent error: \(error)")
                                .font(.system(size: 12))
                                .foregroundStyle(LocusTheme.statusWarn)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button {
                            dismiss()
                        } label: {
                            Label("Return to map", systemImage: "map")
                                .frame(maxWidth: .infinity, minHeight: 38)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(15)
                    .roamSurface(cornerRadius: 20)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("IF IT DOESN'T CONNECT")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(RoamPalette.turquoise)
                        Text("Confirm that the original LocalDevVPN is still connected under Settings → VPN, both radios are OFF for the initial teleport, and your pairing file remains installed. If necessary, reconnect the VPN with cellular ON, then turn cellular OFF and retry. Do not end or reset a working GPS session merely to retry the diagnostics.")
                            .font(.system(size: 12))
                            .foregroundStyle(RoamPalette.muted)
                        Text("Last engine stage: \(LocationEngine.lastStage)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(RoamPalette.muted)
                        Text("Last engine error: \(LocationEngine.lastFailure)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(RoamPalette.muted)
                    }
                    .padding(15)
                    .roamSurface(cornerRadius: 20)

                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            withAnimation { showShortcutsHelp.toggle() }
                        } label: {
                            HStack {
                                Label("Optional: make two iOS Shortcuts", systemImage: "square.stack.3d.up")
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Image(systemName: showShortcutsHelp ? "chevron.up" : "chevron.down")
                            }
                            .foregroundStyle(RoamPalette.turquoise)
                        }
                        .buttonStyle(.plain)
                        if showShortcutsHelp {
                            Text("Create exactly two Shortcuts in Apple's Shortcuts app:\n\n1. ‘Roam Data Off’: Set Cellular Data → Off; then Open App → Roam.\n\n2. ‘Roam Data On’: Set Cellular Data → On; then Open App → Roam.\n\nUse the precise names above. Test both manually first. The shortcuts run visible iOS actions; Roam requests them by name but does not control radios itself. If the Open App step is absent, return to Roam manually within 90 seconds. When already offline you can teleport normally below.")
                                .font(.system(size: 12))
                                .foregroundStyle(RoamPalette.muted)
                            Button {
                                openShortcutsCreator()
                            } label: {
                                Label("Open Shortcuts — create new", systemImage: "square.and.pencil")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(15)
                    .roamSurface(cornerRadius: 20)
                    } // expanded diagnostics and manual steps
                }
                .padding(16)
            }
            .background(RoamPalette.background.ignoresSafeArea())
            .navigationTitle("Wi-Fi-free startup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in
            if autoStartArmed && phase != .active {
                leftAppAfterArming = true
            }
            if restoreRequested && phase != .active {
                restoreLeftApp = true
            }
            if phase != .active && pendingRestoreHandoff != nil {
                // A user leaving to Apple Maps or another app cancels the delayed
                // auto-restore. Their ordinary manual restore remains available.
                pendingRestoreHandoff = nil
                restoreFeedback = "Automatic restore paused because Roam left the foreground. Restore data manually when ready."
            }
            if phase == .active {
                if restoreRequested && restoreLeftApp {
                    restoreReturnedToApp = true
                    observeRestoreReturn()
                }
                if autoStartArmed && leftAppAfterArming {
                    returnedAfterArming = true
                }
                refresh()
                checkArmedAutoStart()
            }
        }
        .onChange(of: network.offlineObserved) { _, _ in
            checkArmedAutoStart()
            observeRestoreReturn()
        }
        .onChange(of: network.cellularPathObserved) { _, _ in
            observeRestoreReturn()
        }
        .onDisappear {
            // A delayed Shortcuts hand-off must not run after the guide is dismissed.
            pendingRestoreHandoff = nil
        }
        .task {
            while !Task.isCancelled {
                refresh()
                if scenePhase == .active { checkArmedAutoStart() }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    /// Optional experimental workflow, starts even if the original LocalDevVPN
    /// profile is currently disconnected. The SHORTCUT (not Roam) requests VPN On.
    private var coldStartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("START WITH VPN DISCONNECTED", systemImage: "power.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.white)
                Spacer()
                Text("TESTED · v0.27")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(RoamPalette.turquoise)
            }
            Text("Cold Start")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("No manual VPN preconnection needed. Your ‘Roam Cold Start’ Shortcut connects the installed LocalDevVPN profile on cellular, goes offline and returns here for one checked teleport. Still depends on LocalDevVPN being installed.")
                .font(.system(size: 12))
                .foregroundStyle(RoamPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if network.wifiPathObserved {
                Label("Turn Wi-Fi OFF in Settings before starting.", systemImage: "wifi.exclamationmark")
                    .font(.system(size: 12))
                    .foregroundStyle(LocusTheme.statusWarn)
            } else if network.offlineObserved {
                Label("Cellular is currently offline. Turn it ON to let Shortcuts connect the VPN first.", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 12))
                    .foregroundStyle(LocusTheme.statusWarn)
            } else if network.cellularPathObserved {
                Label("Cellular route observed · ready for Cold Start setup", systemImage: "checkmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(RoamPalette.turquoise)
            }
            if session.isSpoofing {
                Text("An existing GPS session is active. Use Re-teleport instead of starting a new VPN connection.")
                    .font(.system(size: 12))
                    .foregroundStyle(RoamPalette.muted)
            }
            Button(action: armAndLaunchColdStart) {
                Label("Cold Start · Connect VPN & Teleport", systemImage: "bolt.fill")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(RoamPalette.electricBlue)
            .disabled(!canArmColdStart)
            if coldStartArmed {
                Label("Armed for ONE GPS command. VPN route checking is read-only; expires after 90 seconds.", systemImage: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(LocusTheme.statusWarn)
                Button("Cancel Cold Start", role: .cancel) {
                    cancelAutoStart("Cold Start cancelled. Turn mobile data back on if necessary.")
                }
                .font(.system(size: 12))
                .buttonStyle(.bordered)
            }
            if coldStartArmed || lastColdStartSuccess || coldProbeFeedback != "Not attempted" {
                Text("Local VPN route: \(coldProbeFeedback)")
                    .font(.system(size: 11))
                    .foregroundStyle(lastColdStartSuccess ? RoamPalette.turquoise : RoamPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                withAnimation { showColdStartHelp.toggle() }
            } label: {
                HStack {
                    Label("Create ‘Roam Cold Start’ Shortcut", systemImage: "square.stack.3d.up")
                    Spacer()
                    Image(systemName: showColdStartHelp ? "chevron.up" : "chevron.down")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RoamPalette.turquoise)
            }
            .buttonStyle(.plain)
            if showColdStartHelp {
                Text("In Shortcuts create a third shortcut with EXACT name ‘Roam Cold Start’. Add these actions in order:\n\n1. Set VPN → Connect → select the configured LocalDevVPN VPN profile (choose it from the VPN picker, not typed text).\n2. Wait → 5 seconds.\n3. Set Cellular Data → Off.\n4. Open App → your NEW Roam v0.28.\n\nTest the VPN action separately first: from VPN Disconnected and cellular ON, run Set VPN and confirm Settings → VPN shows Connected. If the VPN is not selectable, use Open LocalDevVPN below instead. Keep existing ‘Roam Data Off’ and ‘Roam Data On’ Shortcuts unchanged. Do NOT add Disconnect VPN.")
                    .font(.system(size: 12))
                    .foregroundStyle(RoamPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Create Shortcut") { openShortcutsCreator() }
                    Button("Open LocalDevVPN") { LocalDevVPN.openOrInstall() }
                }
                .buttonStyle(.bordered)
                .font(.system(size: 11, weight: .medium))
            }
            Text("The route check confirms only local TCP reachability, not VPN ownership or GPS accuracy. If connecting the VPN fails, the auto-teleport won't run. Restore mobile data with the usual Data On button below.")
                .font(.system(size: 11))
                .foregroundStyle(RoamPalette.muted)
        }
        .padding(15)
        .roamSurface(cornerRadius: 20)
    }

    // Kept outside the main ScrollView expression to limit SwiftUI type-check load.
    private var oneTapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("ONE-TAP START ASSISTANCE", systemImage: "bolt.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(RoamPalette.turquoise)
                Spacer()
                Text("TESTED · v0.26")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(RoamPalette.muted)
            }
            Text("Proven method: with Wi-Fi OFF and LocalDevVPN already connected, one tap runs your ‘Roam Data Off’ Shortcut. On return offline, Roam sends ONE teleport. Optional auto-restore launches ‘Roam Data On’ only if the GPS API accepts the command.")
                .font(.system(size: 12))
                .foregroundStyle(RoamPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: $vpnCheckedByUser) {
                Text("I checked LocalDevVPN is Connected in iPhone Settings")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
            .tint(RoamPalette.turquoise)
            if network.wifiPathObserved {
                Label("Wi-Fi is active: turn Wi-Fi OFF before using one-tap startup.", systemImage: "wifi.exclamationmark")
                    .font(.system(size: 12))
                    .foregroundStyle(LocusTheme.statusWarn)
            } else if network.offlineObserved {
                Text("Network already offline: use Teleport below. No need to run the Data Off Shortcut again.")
                    .font(.system(size: 12))
                    .foregroundStyle(RoamPalette.muted)
            }
            Toggle(isOn: $autoRestoreForThisStart) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Automatically run Data On after accepted teleport")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Optional · experimental. If enabled, Roam briefly waits then opens your existing ‘Roam Data On’ Shortcut. Turn off to verify Apple Maps before restoring manually. Switch resets whenever this screen is reopened.")
                        .font(.system(size: 11))
                        .foregroundStyle(RoamPalette.muted)
                }
            }
            .tint(RoamPalette.turquoise)
            .disabled(autoStartArmed || pendingRestoreHandoff != nil)
            if let selected = session.pin {
                Text(String(format: "Armed destination: %.5f, %.5f", selected.latitude, selected.longitude))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(RoamPalette.muted)
            } else {
                Text("First select a destination on Roam's map.")
                    .font(.system(size: 12))
                    .foregroundStyle(LocusTheme.statusWarn)
            }
            Button(action: armAndLaunchDataOff) {
                Label("One-tap: Go offline & start teleport", systemImage: "bolt.fill")
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(RoamPalette.turquoise)
            .disabled(!canArmAutoStart)

            if autoStartArmed {
                Label(coldStartArmed ? "Cold Start armed: waiting for VPN route, then ONE teleport (90 seconds)." : "Armed for ONE teleport on return, while offline (expires after 90 seconds).", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 12))
                    .foregroundStyle(LocusTheme.statusWarn)
                Button("Cancel armed teleport", role: .cancel) { cancelAutoStart("Automatic start cancelled; no teleport sent") }
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.bordered)
            }
            Text(oneTapFeedback)
                .font(.system(size: 12))
                .foregroundStyle(autoStartAcceptedLocally ? RoamPalette.turquoise : RoamPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if autoStartAcceptedLocally {
                Text("Local GPS API accepted the request; open Apple Maps to independently verify the blue dot before relying on it.")
                    .font(.system(size: 11))
                    .foregroundStyle(RoamPalette.muted)
                manualMapsVerificationCard
            }

            if autoStartAcceptedLocally && network.offlineObserved && !restoreRequested {
                VStack(alignment: .leading, spacing: 8) {
                    Label("TELEPORT ACCEPTED — RESTORE CELLULAR", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(RoamPalette.turquoise)
                    Text("Apple Maps verification is separate from the API result. You can restore mobile data when ready; Roam will keep the current simulated location.")
                        .font(.system(size: 11))
                        .foregroundStyle(RoamPalette.muted)
                    Button(action: runDataOnShortcut) {
                        Label("Restore mobile data now", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(RoamPalette.turquoise)
                    .disabled(pendingRestoreHandoff != nil)
                    if pendingRestoreHandoff != nil {
                        Button("Cancel automatic restore") {
                            pendingRestoreHandoff = nil
                            restoreFeedback = "Automatic restore cancelled; use the manual restore button when ready."
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .buttonStyle(.bordered)
                    }
                }
                .padding(12)
                .background(RoamPalette.turquoise.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
            }
            if restoreRequested || restoreReturnedToApp {
                Label(restoreFeedback, systemImage: network.cellularPathObserved ? "antenna.radiowaves.left.and.right" : "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(network.cellularPathObserved && restoreReturnedToApp ? RoamPalette.turquoise : RoamPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: runDataOnShortcut) {
                Label("Restore mobile data — Run ‘Roam Data On’", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            Text("Restore mobile data even if teleport fails. If a Shortcut is missing, use iPhone Settings → Mobile Data. Roam cannot verify or silently change the cellular toggle.")
                .font(.system(size: 11))
                .foregroundStyle(RoamPalette.muted)
        }
        .padding(15)
        .roamSurface(cornerRadius: 20)
    }

    // A deliberate, independent human observation. We never claim that API
    // acceptance proves the Apple Maps blue dot moved. Each run can be counted
    // once, and no coordinates are retained.
    private var manualMapsVerificationCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("APPLE MAPS CHECK", systemImage: "map.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(RoamPalette.turquoise)
            if mapsVerificationPending {
                Text("Open Apple Maps, check its blue dot against your chosen destination, then return and record what you observed. No automatic GPS verification is claimed.")
                    .font(.system(size: 11))
                    .foregroundStyle(RoamPalette.muted)
                Button {
                    mapsConfirmed += 1
                    mapsVerificationPending = false
                    mapsVerificationStatus = "You confirmed that Apple Maps matched."
                } label: {
                    Label("Apple Maps matched", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .tint(RoamPalette.turquoise)
                Button {
                    mapsNotMatched += 1
                    mapsVerificationPending = false
                    mapsVerificationStatus = "You reported no match. Preserve the session; check the route and pairing diagnostics."
                    recoverySuggested = true
                } label: {
                    Label("Apple Maps did not match", systemImage: "exclamationmark.triangle")
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.bordered)
            } else if !mapsVerificationStatus.isEmpty {
                Text(mapsVerificationStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(RoamPalette.muted)
            }
        }
        .padding(12)
        .background(RoamPalette.electricBlue.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
    }

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("STARTUP NEEDS ATTENTION", systemImage: "cross.case.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(LocusTheme.statusWarn)
            Text("First restore mobile data. Confirm the original LocalDevVPN profile is connected and keep the saved pairing file. With Wi-Fi off, retry Cold Start, or use the established VPN-connected One-Tap option. Do not reset a working GPS session.")
                .font(.system(size: 12))
                .foregroundStyle(RoamPalette.muted)
            Button(action: runDataOnShortcut) {
                Label("Restore mobile data", systemImage: "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.borderedProminent)
            .tint(RoamPalette.turquoise)
            Button {
                LocalDevVPN.openOrInstall()
            } label: {
                Label("Open LocalDevVPN", systemImage: "shield.lefthalf.filled")
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.bordered)
        }
        .padding(15)
        .roamSurface(cornerRadius: 20)
    }

    private var reliabilityPlanCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showReliabilityPlan.toggle() }
            } label: {
                HStack {
                    Label("Reliability test · 3 clean starts", systemImage: "checkmark.shield.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: showReliabilityPlan ? "chevron.up" : "chevron.down")
                        .foregroundStyle(RoamPalette.turquoise)
                }
            }
            .buttonStyle(.plain)
            if showReliabilityPlan {
                Text("Repeat from a genuinely disconnected VPN three times: Wi-Fi OFF, cellular ON → Cold Start → offline teleport → Apple Maps blue dot → restore data → re-teleport. Finish by trying a short background cruise and confirming live movement in Apple Maps. If a test fails, copy the safe summary under Diagnostics and use manual recovery. API counters alone do not establish reliability.")
                    .font(.system(size: 12))
                    .foregroundStyle(RoamPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .roamSurface(cornerRadius: 18)
    }

    private var startupDiagnosticsSummary: String {
        [
            "Roam v0.28 — user-copied startup summary",
            "Timestamp (UTC): \(ISO8601DateFormatter().string(from: Date()))",
            "Network path: \(network.pathDescription)",
            "Pairing file present: \(pairing.hasPairingFile)",
            "VPN-like candidate visible (unverified): \(vpnCandidateVisible)",
            "Retained GPS handle: \(retainedHandle)",
            "Simulation active: \(session.isSpoofing)",
            "One-Tap total attempts: \(oneTapStarts)",
            "Local API accepted: \(oneTapAccepted)",
            "Local API failed: \(oneTapFailed)",
            "VPN-disconnected Cold Start attempts: \(coldStarts)",
            "Cold Start API accepted: \(coldAccepted)",
            "Cold Start failed or expired: \(coldFailures)",
            "Data On Shortcut launches requested: \(restoreRequests)",
            "Observed cellular-path returns: \(cellularPathReturns)",
            "Apple Maps matched (user-reported): \(mapsConfirmed)",
            "Apple Maps not matched (user-reported): \(mapsNotMatched)",
            "No coordinates, pairing credentials, files or endpoint addresses included."
        ].joined(separator: "\n")
    }

    // A few local, aggregate counters make repeated test runs comparable.
    // Their numbers are not claims of Apple Maps verification or actual 5G availability.
    private var reliabilityCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("STARTUP RELIABILITY · v0.28", systemImage: "chart.bar.xaxis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(RoamPalette.turquoise)
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Starts")
                        .foregroundStyle(RoamPalette.muted)
                    Text("\(oneTapStarts)").font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 3) {
                    Text("API accepted")
                        .foregroundStyle(RoamPalette.muted)
                    Text("\(oneTapAccepted)").font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(RoamPalette.turquoise)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 3) {
                    Text("API failed")
                        .foregroundStyle(RoamPalette.muted)
                    Text("\(oneTapFailed)").font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .font(.system(size: 11))
            Text("Restore Shortcut launches: \(restoreRequests) · Cellular-path returns: \(cellularPathReturns)")
                .font(.system(size: 11))
                .foregroundStyle(RoamPalette.muted)
            Text("VPN-disconnected Cold Starts: \(coldStarts) · API accepted: \(coldAccepted) · Failed/expired: \(coldFailures)")
                .font(.system(size: 11))
                .foregroundStyle(RoamPalette.muted)
            Text("Apple Maps confirmations (user-reported): \(mapsConfirmed) · Did not match: \(mapsNotMatched)")
                .font(.system(size: 11))
                .foregroundStyle(RoamPalette.muted)
            Text("Counts stay on this iPhone. API acceptance, a VPN interface candidate and a cellular path are not independent proof that GPS or network settings changed.")
                .font(.system(size: 11))
                .foregroundStyle(RoamPalette.muted)
            Button("Reset reliability counters", role: .destructive) {
                oneTapStarts = 0
                oneTapAccepted = 0
                oneTapFailed = 0
                restoreRequests = 0
                cellularPathReturns = 0
                coldStarts = 0
                coldAccepted = 0
                coldFailures = 0
                mapsConfirmed = 0
                mapsNotMatched = 0
            }
            .font(.system(size: 12))
            .buttonStyle(.bordered)
            .disabled(autoStartArmed || pendingRestoreHandoff != nil)
            Button {
                UIPasteboard.general.string = startupDiagnosticsSummary
                summaryCopied = true
            } label: {
                Label(summaryCopied ? "Summary copied" : "Copy safe startup summary", systemImage: "doc.on.doc")
            }
            .font(.system(size: 12, weight: .semibold))
            .buttonStyle(.bordered)
            Text("The copied summary contains counts and boolean connection indicators only — no coordinates, pairing file contents or tunnel credentials.")
                .font(.system(size: 11))
                .foregroundStyle(RoamPalette.muted)
            Divider().overlay(RoamPalette.muted.opacity(0.3))
            Label("Quick recovery", systemImage: "cross.case")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
            Text("If Cold Start fails, restore mobile data first; check the configured LocalDevVPN VPN profile and reopen it manually if necessary. Then use the verified v0.26 One-Tap path. Never delete the VPN profile, pairing data or a retained working GPS session during troubleshooting. The Restore Mobile Data button remains available even on failures.")
                .font(.system(size: 12))
                .foregroundStyle(RoamPalette.muted)
        }
        .padding(15)
        .roamSurface(cornerRadius: 20)
    }

    /// iOS Shortcuts URL scheme is documented by Apple. Opening Shortcuts is
    /// user-visible, and does not grant Roam direct access to cellular settings.
    private func shortcutURL(named name: String) -> URL? {
        var parts = URLComponents()
        parts.scheme = "shortcuts"
        parts.host = "run-shortcut"
        parts.queryItems = [URLQueryItem(name: "name", value: name)]
        return parts.url
    }

    private func armAndLaunchDataOff() {
        guard canArmAutoStart, let coordinate = session.pin else { return }
        coldStartArmed = false
        coldProbeApproved = false
        coldProbeGeneration = UUID()
        coldProbeFeedback = "Not attempted"
        lastColdStartSuccess = false
        mapsVerificationPending = false
        mapsVerificationStatus = ""
        recoverySuggested = false
        summaryCopied = false
        autoStartPin = coordinate // Snapshot: never follow a moving pin without consent.
        autoStartArmedAt = Date()
        autoStartArmed = true
        leftAppAfterArming = false
        returnedAfterArming = false
        autoStartAcceptedLocally = false
        pendingRestoreHandoff = nil
        restoreRequested = false
        restoreLeftApp = false
        restoreReturnedToApp = false
        cellularReturnRecorded = false
        restoreFeedback = "No restore requested yet"
        oneTapStarts += 1
        oneTapFeedback = "Opening ‘Roam Data Off’… Return to Roam with cellular OFF."
        guard let url = shortcutURL(named: "Roam Data Off") else {
            cancelAutoStart("Could not construct Shortcuts URL; use manual start")
            return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened {
                DispatchQueue.main.async {
                    cancelAutoStart("Shortcuts did not open. Create ‘Roam Data Off’ or use iPhone Settings.")
                }
            }
        }
    }

    private func armAndLaunchColdStart() {
        guard canArmColdStart, let coordinate = session.pin else { return }
        autoStartPin = coordinate
        autoStartArmedAt = Date()
        autoStartArmed = true
        coldStartArmed = true
        coldProbeApproved = false
        coldProbeRunning = false
        coldProbeNextAttemptAt = .distantPast
        coldProbeGeneration = UUID()
        coldProbeFeedback = "Waiting for the VPN to connect and the offline return"
        lastColdStartSuccess = false
        mapsVerificationPending = false
        mapsVerificationStatus = ""
        recoverySuggested = false
        summaryCopied = false
        leftAppAfterArming = false
        returnedAfterArming = false
        autoStartAcceptedLocally = false
        pendingRestoreHandoff = nil
        restoreRequested = false
        restoreLeftApp = false
        restoreReturnedToApp = false
        cellularReturnRecorded = false
        restoreFeedback = "No restore requested yet"
        oneTapStarts += 1
        coldStarts += 1
        oneTapFeedback = "Opening ‘Roam Cold Start’. It should connect the VPN before disabling cellular data."
        guard let url = shortcutURL(named: "Roam Cold Start") else {
            failColdStart("Could not create the Shortcuts URL; use the manual setup")
            return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened {
                DispatchQueue.main.async {
                    failColdStart("Shortcuts did not open. Create ‘Roam Cold Start’ or use the existing workflow.")
                }
            }
        }
    }

    private func failColdStart(_ message: String) {
        if coldStartArmed { coldFailures += 1 }
        cancelAutoStart(message)
        recoverySuggested = true
    }

    /// Read-only local reachability. It runs off the main thread and never touches
    /// the developer pairing or GPS handle. A matching utun is only a candidate.
    private func probeColdStartRouteIfNeeded() {
        guard autoStartArmed, coldStartArmed, !coldProbeRunning,
              Date() >= coldProbeNextAttemptAt else { return }
        coldProbeRunning = true
        coldProbeNextAttemptAt = Date().addingTimeInterval(4)
        coldProbeFeedback = "Testing VPN peer over the offline route…"
        let generation = coldProbeGeneration
        let endpointIP = TunnelConfig.targetIP
        let endpointPort = TunnelConfig.targetPort
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = RoamBoundTCPProbe.check(host: endpointIP, port: endpointPort, interface: nil)
            DispatchQueue.main.async {
                guard coldProbeGeneration == generation, autoStartArmed,
                      coldStartArmed else { return }
                coldProbeRunning = false
                coldProbeFeedback = outcome
                if outcome == "TCP connected" {
                    coldProbeApproved = true
                    oneTapFeedback = "Offline VPN peer is reachable. Attempting your one authorized teleport…"
                    checkArmedAutoStart()
                } else {
                    oneTapFeedback = "VPN route not reachable yet (\(outcome)). Waiting briefly; if it remains unavailable, restore mobile data."
                }
            }
        }
    }

    private func runDataOnShortcut() {
        // Safety: never allow a pending GPS teleport or a delayed duplicate restore
        // to remain armed when the user explicitly requests cellular restoration.
        if autoStartArmed { cancelAutoStart("Automatic teleport cancelled before restoring cellular") }
        pendingRestoreHandoff = nil
        restoreRequested = true
        restoreLeftApp = false
        restoreReturnedToApp = false
        restoreFeedback = "Opening ‘Roam Data On’… confirm cellular service returns."
        guard let url = shortcutURL(named: "Roam Data On") else {
            restoreRequested = false
            restoreFeedback = "Could not create the restore link. Use Settings → Mobile Data → On."
            return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
            DispatchQueue.main.async {
                if opened {
                    restoreRequests += 1
                } else {
                    restoreRequested = false
                    restoreFeedback = "Shortcuts could not open. Restore Mobile Data manually in Settings."
                }
            }
        }
    }

    /// The app cannot read the actual cellular radio toggle. On a return from
    /// Shortcuts we only note that NWPathMonitor saw a cellular route; users
    /// should verify mobile service and GPS in their other apps.
    private func observeRestoreReturn() {
        guard restoreRequested, restoreReturnedToApp else { return }
        if network.cellularPathObserved {
            restoreFeedback = "Cellular network path observed after restore; verify mobile service and Apple Maps."
            if !cellularReturnRecorded {
                cellularReturnRecorded = true
                cellularPathReturns += 1
            }
        } else {
            restoreFeedback = "Returned to Roam; cellular path not yet observed. Check the Data On Shortcut or iPhone Settings."
        }
    }

    /// Experimental optional second Shortcuts hand-off. Only after a user-armed
    /// one-shot teleport and an API-accepted result. Cancels if the guide closes,
    /// the app becomes inactive, a second start begins, or the user cancels.
    private func scheduleAutoRestoreIfRequested() {
        guard autoRestoreForThisStart, autoStartAcceptedLocally, network.offlineObserved else { return }
        let token = UUID()
        pendingRestoreHandoff = token
        oneTapFeedback = "Teleport API accepted. Automatic cellular restore is armed; you can cancel below."
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard pendingRestoreHandoff == token else { return }
            guard scenePhase == .active, autoStartAcceptedLocally,
                  network.offlineObserved, !autoStartArmed, !restoreRequested else {
                pendingRestoreHandoff = nil
                restoreFeedback = "Automatic restore not launched; use the manual restore button when ready."
                return
            }
            pendingRestoreHandoff = nil
            runDataOnShortcut()
        }
    }

    private func openShortcutsCreator() {
        guard let url = URL(string: "shortcuts://create-shortcut") else { return }
        UIApplication.shared.open(url)
    }

    private func cancelAutoStart(_ message: String) {
        coldStartArmed = false
        coldProbeApproved = false
        coldProbeRunning = false
        coldProbeGeneration = UUID() // invalidate any delayed socket callback
        autoStartArmed = false
        leftAppAfterArming = false
        returnedAfterArming = false
        autoStartPin = nil
        autoStartArmedAt = nil
        oneTapFeedback = message
    }

    /// One-shot on *explicit* opt-in only. Never starts after a timeout, and
    /// never assumes a VPN belongs to LocalDevVPN based on a utun name.
    private func checkArmedAutoStart() {
        guard autoStartArmed else { return }
        guard let armedAt = autoStartArmedAt, Date().timeIntervalSince(armedAt) < autoStartTimeout else {
            if coldStartArmed { coldFailures += 1 }
            cancelAutoStart("The 90-second startup window expired. Restore mobile data and try again if needed.")
            recoverySuggested = true
            return
        }
        guard returnedAfterArming, scenePhase == .active, network.offlineObserved else { return }
        guard !session.isBusy, pairing.hasPairingFile, let coordinate = autoStartPin else { return }

        if coldStartArmed {
            if session.isSpoofing {
                failColdStart("An active GPS session was found; Cold Start cancelled to protect the retained connection.")
                return
            }
            guard vpnCandidateVisible else {
                oneTapFeedback = "Returned offline. Waiting for a VPN interface… If it remains absent, restore mobile data and connect LocalDevVPN manually."
                return
            }
            guard coldProbeApproved else {
                probeColdStartRouteIfNeeded()
                return
            }
        }

        let wasColdStart = coldStartArmed
        // Disarm BEFORE invoking the location engine. A path/lifecycle update
        // must never result in a second unintended GPS command.
        autoStartArmed = false
        coldStartArmed = false
        coldProbeGeneration = UUID()
        autoStartPin = nil
        autoStartArmedAt = nil
        returnedAfterArming = false
        leftAppAfterArming = false
        session.teleport(to: coordinate, pairing: pairing)
        autoStartAcceptedLocally = session.lastTeleportResult.hasPrefix("Initial teleport sent") ||
            session.lastTeleportResult.hasPrefix("Persistent teleport sent")
        if autoStartAcceptedLocally {
            recoverySuggested = false
            mapsVerificationPending = true
            mapsVerificationStatus = "Awaiting independent Apple Maps check"
            oneTapAccepted += 1
            if wasColdStart { coldAccepted += 1; lastColdStartSuccess = true }
            oneTapFeedback = wasColdStart
                ? "VPN-off startup: GPS API accepted the teleport. Verify Apple Maps; restore cellular when ready."
                : "One-shot teleport request accepted. Restore mobile data when ready."
            scheduleAutoRestoreIfRequested()
        } else {
            oneTapFailed += 1
            if wasColdStart { coldFailures += 1 }
            mapsVerificationPending = false
            recoverySuggested = true
            oneTapFeedback = "Teleport request failed: \(session.lastTeleportResult). Restore mobile data if needed and check LocalDevVPN."
        }
    }

    private func refresh() {
        vpnCandidateVisible = LocalDevVPN.tunnelCandidate != nil
    }

    private func stateRow(_ label: String, _ detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(RoamPalette.turquoise)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 4)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(RoamPalette.muted)
                .multilineTextAlignment(.trailing)
        }
    }

    private func step(_ number: Int, title: String, note: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(RoamPalette.background)
                .frame(width: 25, height: 25)
                .background(RoamPalette.turquoise, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(RoamPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private final class OfflineStartupNetworkObserver: ObservableObject {
    @Published private(set) var pathDescription = "Checking…"
    @Published private(set) var offlineObserved = false
    @Published private(set) var wifiPathObserved = false
    @Published private(set) var cellularPathObserved = false
    @Published private(set) var hasCheckedPath = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "roam.offline-startup.network")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isOffline = path.status != .satisfied
            let label: String
            if isOffline {
                label = "No usable uplink reported"
            } else if path.usesInterfaceType(.wifi) {
                label = "Wi-Fi active"
            } else if path.usesInterfaceType(.cellular) {
                label = "Cellular active"
            } else {
                label = "Other / VPN path"
            }
            let usesWiFi = path.status == .satisfied && path.usesInterfaceType(.wifi)
            DispatchQueue.main.async { [weak self] in
                self?.offlineObserved = isOffline
                self?.wifiPathObserved = usesWiFi
                self?.cellularPathObserved = path.status == .satisfied && path.usesInterfaceType(.cellular)
                self?.pathDescription = label
                self?.hasCheckedPath = true
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
