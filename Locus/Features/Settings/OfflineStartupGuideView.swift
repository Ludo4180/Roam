import SwiftUI
import Network
import CoreLocation

/// v0.26: opt-in Shortcuts-assisted Wi-Fi-free startup and explicit auto-restore hand-off.
/// Shortcuts are created and run by the user. Roam can arm one finite,
/// foreground-only teleport after the user returns while the network is offline.
/// Never silently changes radios, resets the VPN, or clears a retained GPS handle.
struct OfflineStartupGuideView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var network = OfflineStartupNetworkObserver()
    @State private var vpnCandidateVisible = LocalDevVPN.tunnelCandidate != nil
    @State private var attemptedFromGuide = false
    @State private var showShortcutsHelp = false

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
    private let autoStartTimeout: TimeInterval = 90

    private var canArmAutoStart: Bool {
        vpnCheckedByUser && pairing.hasPairingFile && session.pin != nil &&
        !session.isBusy && network.hasCheckedPath &&
        !network.wifiPathObserved && !network.offlineObserved && !autoStartArmed
    }

    private var retainedHandle: Bool { LocationEngine.isSessionActive }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Start Roam without Wi-Fi")
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Your confirmed Wi-Fi-free workflow uses a pre-connected LocalDevVPN. v0.26 can optionally run your existing ‘Roam Data On’ Shortcut after an accepted teleport, but only when you explicitly enable it for that attempt.")
                        .font(.subheadline)
                        .foregroundStyle(RoamPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)

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

                    oneTapCard

                    reliabilityCard

                    VStack(alignment: .leading, spacing: 12) {
                        step(1, title: "Connect LocalDevVPN", note: "With mobile data ON, connect the original LocalDevVPN. Check Settings → VPN says Connected. Do not replace the working VPN.")
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

    // Kept outside the main ScrollView expression to limit SwiftUI type-check load.
    private var oneTapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("ONE-TAP START ASSISTANCE", systemImage: "bolt.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(RoamPalette.turquoise)
                Spacer()
                Text("NEW · v0.26")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(RoamPalette.muted)
            }
            Text("With Wi-Fi OFF and LocalDevVPN already connected, one tap runs your ‘Roam Data Off’ Shortcut. On return offline, Roam sends ONE teleport. Optional auto-restore launches ‘Roam Data On’ only if the GPS API accepts the command.")
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
                Label("Armed for ONE teleport on return, while offline (expires after 90 seconds).", systemImage: "clock.arrow.circlepath")
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

    // A few local, aggregate counters make repeated test runs comparable.
    // Their numbers are not claims of Apple Maps verification or actual 5G availability.
    private var reliabilityCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("STARTUP RELIABILITY · v0.26", systemImage: "chart.bar.xaxis")
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
            Text("Counts are stored only on this iPhone. An accepted API command is not independent Apple Maps verification; a cellular network path does not prove the radio switch state.")
                .font(.system(size: 11))
                .foregroundStyle(RoamPalette.muted)
            Button("Reset reliability counters", role: .destructive) {
                oneTapStarts = 0
                oneTapAccepted = 0
                oneTapFailed = 0
                restoreRequests = 0
                cellularPathReturns = 0
            }
            .font(.system(size: 12))
            .buttonStyle(.bordered)
            .disabled(autoStartArmed || pendingRestoreHandoff != nil)
            Divider().overlay(RoamPalette.muted.opacity(0.3))
            Label("Quick recovery", systemImage: "cross.case")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
            Text("If offline startup fails, leave the retained session alone. Check VPN connected, pairing file available and both radios off. Retry the normal Teleport button. If VPN disconnected, restore cellular first, reconnect the original LocalDevVPN, then repeat the one-tap sequence. The Restore Mobile Data button remains available even on failures.")
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
            cancelAutoStart("The 90-second startup window expired. Start again if needed.")
            return
        }
        guard returnedAfterArming, scenePhase == .active, network.offlineObserved else { return }
        guard !session.isBusy, pairing.hasPairingFile, let coordinate = autoStartPin else { return }

        // Disarm BEFORE invoking the location engine. A path/lifecycle update
        // must never result in a second unintended GPS command.
        autoStartArmed = false
        autoStartPin = nil
        autoStartArmedAt = nil
        returnedAfterArming = false
        leftAppAfterArming = false
        session.teleport(to: coordinate, pairing: pairing)
        autoStartAcceptedLocally = session.lastTeleportResult.hasPrefix("Initial teleport sent") ||
            session.lastTeleportResult.hasPrefix("Persistent teleport sent")
        if autoStartAcceptedLocally {
            oneTapAccepted += 1
            oneTapFeedback = "One-shot teleport request accepted. Restore mobile data when ready."
            scheduleAutoRestoreIfRequested()
        } else {
            oneTapFailed += 1
            oneTapFeedback = "Teleport request failed: \(session.lastTeleportResult). Check LocalDevVPN and retry manually."
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
