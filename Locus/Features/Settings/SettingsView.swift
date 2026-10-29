import SwiftUI
import Network
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    @State private var probeResult = "Not tested"
    @State private var probeConnection: NWConnection?
    @State private var showImporter = false
    @State private var showPairOnDevice = false
    @State private var tunnelIP = TunnelConfig.targetIP
    @State private var developerPort = String(TunnelConfig.targetPort)
    @State private var localDevVPNInstalled = LocalDevVPN.isInstalled
    @Environment(\.scenePhase) private var scenePhase

    private var supportsOnDevicePairing: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text(pairing.hasPairingFile ? "RPPairing file installed" : "No pairing file")
                    } icon: {
                        Image(systemName: pairing.hasPairingFile ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(pairing.hasPairingFile ? LocusTheme.statusGood : LocusTheme.statusWarn)
                    }

                    if supportsOnDevicePairing {
                        Button {
                            showPairOnDevice = true
                        } label: {
                            Label("Pair on this iPhone", systemImage: "iphone.gen3.radiowaves.left.and.right")
                        }
                    }

                    Button("Import RPPairing file…") { showImporter = true }
                    Button("Paste RPPairing from clipboard") {
                        do {
                            try pairing.importPairingFromClipboard()
                        } catch {
                            session.lastError = error.localizedDescription
                        }
                    }
                    if pairing.hasPairingFile {
                        Button("Remove pairing file", role: .destructive) {
                            try? pairing.removePairing()
                        }
                    }
                } header: {
                    Text("Developer pairing")
                } footer: {
                    Text(supportsOnDevicePairing
                         ? "On iOS 27, use Pair on this iPhone — no computer. Roam advertises a pairable host; confirm the 6-digit code under Settings › Privacy & Security › Developer Mode › Pair with Host. On older iOS, import an RPPairing file from idevice_pair (not a SideStore lockdown .mobiledevicepairing). LiveContainer: enable Fix File Picker on Roam, or use Paste / Share → LiveContainer → Roam."
                         : "Import an RPPairing file from idevice_pair (not a SideStore lockdown .mobiledevicepairing). If the file picker fails (common in LiveContainer), enable Fix File Picker on the app, share the file into LiveContainer → Roam, or copy the plist and use Paste.")
                }

                Section {
                    TextField("Device tunnel IP", text: $tunnelIP)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            TunnelConfig.setTargetIP(tunnelIP)
                        }
                    LabeledContent("VPN interface") {
                        Text(LocalDevVPN.isConnected ? "Detected" : "Not detected")
                            .foregroundStyle(LocalDevVPN.isConnected ? LocusTheme.statusGood : LocusTheme.statusWarn)
                    }
                    Button("Save tunnel IP") {
                        TunnelConfig.setTargetIP(tunnelIP)
                    }
                    TextField("Developer port (default 49152)", text: $developerPort)
                        .keyboardType(.numberPad)
                    Button("Save developer port") {
                        TunnelConfig.setTargetPort(developerPort)
                    }
                    Button("Test developer endpoint (TCP selected port)") {
                        TunnelConfig.setTargetIP(tunnelIP)
                        TunnelConfig.setTargetPort(developerPort)
                        testDeveloperEndpoint()
                    }
                    LabeledContent("Endpoint diagnostic", value: probeResult)
                    LabeledContent("Last engine stage", value: LocationEngine.lastStage)
                    LabeledContent("Last engine failure", value: LocationEngine.lastFailure)
                        .font(.footnote)
                    Text("This checks TCP reachability only, not developer pairing or GPS simulation. Test once with cellular off, then again with cellular on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        if localDevVPNInstalled {
                            LocalDevVPN.openInstalled()
                        } else {
                            LocalDevVPN.openAppStore()
                        }
                    } label: {
                        Label(
                            localDevVPNInstalled ? "Open LocalDevVPN" : "Get LocalDevVPN (App Store)",
                            systemImage: localDevVPNInstalled ? "lock.shield.fill" : "arrow.down.app.fill"
                        )
                    }
                } header: {
                    Text("Tunnel")
                } footer: {
                    Text("The VPN indicator only detects a local network interface; it does not prove the Apple developer tunnel is reachable. Start a new teleport on Wi-Fi first; movement may continue over mobile data.")
                }

                Section("CELLULAR RESEARCH — v0.8") {
                    NavigationLink {
                        CellularResearchView()
                    } label: {
                        Label("Wi-Fi / 5G tunnel diagnostics", systemImage: "network.badge.shield.half.filled")
                    }
                    Text("Read-only endpoint and paired-handshake tests. Does not modify GPS, pairing, or VPN settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("YOUR PRIVACY") {
                    Text("Fully on-device. Favorites and recents stay in UserDefaults. No analytics, no accounts, nothing uploaded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("ABOUT ROAM") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Engine", value: "idevice DVT location simulation")
                    Text("Roam v0.5 uses components from Locus (MIT). Location injection uses the MIT-licensed idevice FFI.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

            }
            .navigationTitle("Roam settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        TunnelConfig.setTargetIP(tunnelIP)
                        TunnelConfig.setTargetPort(developerPort)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showImporter) {
            PairingDocumentPicker(
                onPick: { url in
                    showImporter = false
                    do {
                        try pairing.importPairing(from: url)
                    } catch {
                        session.lastError = error.localizedDescription
                    }
                },
                onCancel: { showImporter = false }
            )
            .ignoresSafeArea()
        }
            .sheet(isPresented: $showPairOnDevice) {
                PairOnDeviceView()
                    .environmentObject(pairing)
            }
            .onAppear {
                localDevVPNInstalled = LocalDevVPN.isInstalled
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    localDevVPNInstalled = LocalDevVPN.isInstalled
                }
            }
        }
    }

    private func testDeveloperEndpoint() {
        probeConnection?.cancel()
        probeResult = "Testing…"
        guard let port = NWEndpoint.Port(rawValue: TunnelConfig.targetPort) else {
            probeResult = "Invalid port"
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(tunnelIP), port: port, using: .tcp)
        probeConnection = connection
        connection.stateUpdateHandler = { state in
            DispatchQueue.main.async {
                guard self.probeConnection === connection else { return }
                switch state {
                case .ready:
                    self.probeResult = "TCP reachable"
                    connection.cancel()
                    self.probeConnection = nil
                case .failed(let error):
                    self.probeResult = "TCP failed: \(error.localizedDescription)"
                    connection.cancel()
                    self.probeConnection = nil
                default:
                    break
                }
            }
        }
        connection.start(queue: DispatchQueue(label: "roam.endpoint.diagnostic"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard self.probeConnection === connection else { return }
            self.probeResult = "TCP timed out (5 seconds)"
            connection.cancel()
            self.probeConnection = nil
        }
    }
}

struct PlacesView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss

    @State private var placeToRename: SavedPlace?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                Section("FAVORITES") {
                    if session.favorites.isEmpty {
                        Text("Star a pin from the map to save it.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.favorites) { place in
                        placeButton(place)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    session.removeFavorite(place)
                                } label: {
                                    Label("Delete", systemImage: "trash.fill")
                                }
                                Button {
                                    placeToRename = place
                                    renameText = place.name
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.gray)
                            }
                    }
                }

                Section("RECENT DESTINATIONS") {
                    if session.recents.isEmpty {
                        Text("Teleports show up here.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.recents) { place in
                        placeButton(place)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    session.removeRecent(place)
                                } label: {
                                    Label("Delete", systemImage: "trash.fill")
                                }
                            }
                    }
                }
            }
            .navigationTitle("Saved places")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename Favorite", isPresented: Binding(
                get: { placeToRename != nil },
                set: { if !$0 { placeToRename = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {
                    placeToRename = nil
                }
                Button("Save") {
                    if let place = placeToRename {
                        session.renameFavorite(place, to: renameText)
                    }
                    placeToRename = nil
                }
            } message: {
                Text("Choose a name you’ll recognize later.")
            }
        }
    }

    private func placeButton(_ place: SavedPlace) -> some View {
        Button {
            session.teleport(to: place.coordinate, pairing: pairing)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).foregroundStyle(.primary)
                Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
