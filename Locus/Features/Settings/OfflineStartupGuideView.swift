import SwiftUI
import Network
import CoreLocation

/// v0.24: guidance for the Wi-Fi-free startup sequence established on this device.
/// This view never alters cellular radios, VPN settings or a retained GPS handle.
struct OfflineStartupGuideView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var network = OfflineStartupNetworkObserver()
    @State private var vpnCandidateVisible = LocalDevVPN.tunnelCandidate != nil
    @State private var attemptedFromGuide = false
    @State private var showShortcutsHelp = false

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
                            Text("In Apple's Shortcuts app create ‘Roam Data Off’ with the Set Cellular Data → Off action, and ‘Roam Data On’ with Set Cellular Data → On. Run the first after connecting LocalDevVPN, teleport while offline, then run the second. Test each shortcut manually. Roam does not trigger them or control mobile data itself.")
                                .font(.system(size: 12))
                                .foregroundStyle(RoamPalette.muted)
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
            if phase == .active { refresh() }
        }
        .task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
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
            DispatchQueue.main.async { [weak self] in
                self?.offlineObserved = isOffline
                self?.pathDescription = label
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
