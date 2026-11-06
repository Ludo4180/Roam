import SwiftUI
import Network
import CoreLocation

/// v0.25: opt-in Shortcuts-assisted Wi-Fi-free startup.
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
                    Text("This workflow has worked on your iPhone with LocalDevVPN already connected. Switch mobile data off briefly to start a new simulation, then switch it back on. Nothing is changed automatically.")
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
            if phase == .active {
                if autoStartArmed && leftAppAfterArming {
                    returnedAfterArming = true
                }
                refresh()
                checkArmedAutoStart()
            }
        }
        .onChange(of: network.offlineObserved) { _, _ in
            checkArmedAutoStart()
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
                Text("NEW · v0.25")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(RoamPalette.muted)
            }
            Text("With Wi-Fi OFF and LocalDevVPN already connected, one tap runs your ‘Roam Data Off’ Shortcut. When it brings you back to Roam and the network reports offline, Roam sends ONE teleport to your selected pin.")
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
        // Safety: never leave a pending automatic teleport while restoring data.
        if autoStartArmed { cancelAutoStart("Automatic teleport cancelled before restoring cellular") }
        oneTapFeedback = "Opening ‘Roam Data On’… Confirm mobile data is restored in iPhone Settings."
        guard let url = shortcutURL(named: "Roam Data On") else {
            oneTapFeedback = "Could not create the restore link. Use Settings → Mobile Data → On."
            return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened {
                DispatchQueue.main.async {
                    oneTapFeedback = "Shortcuts could not open. Restore Mobile Data manually in Settings."
                }
            }
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
        oneTapFeedback = autoStartAcceptedLocally
            ? "One-shot teleport request accepted. Restore mobile data when ready."
            : "Teleport request failed: \(session.lastTeleportResult). Check LocalDevVPN and retry manually."
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
                self?.pathDescription = label
                self?.hasCheckedPath = true
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
