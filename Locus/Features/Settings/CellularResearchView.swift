import Darwin
import Foundation
import Network
import SwiftUI
import UIKit
import idevice

/// Read-only diagnostics. This screen never changes VPN routes, the stored pairing,
/// or Roam's location simulation session.
struct CellularResearchView: View {
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var session: SpoofSession
    @StateObject private var research = CellularResearchModel()
    @State private var portText = String(TunnelConfig.targetPort)
    @State private var handshakeHost = "10.7.0.1"
    @State private var comparisonHost = "10.7.0.1"

    private let endpoints = ["10.7.0.1", "127.0.0.1", "::1"]

    private var safeToProbe: Bool {
        !session.isSpoofing && !LocationEngine.isSessionActive
    }

    private func routeFinding(_ label: String, result: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline.weight(.semibold))
            Text(result).font(.footnote.monospaced()).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func routeSnapshot(_ snapshot: RoamRouteAuditSnapshot, title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.semibold))
            Text("\(snapshot.date) · \(snapshot.transport) · port \(snapshot.port)")
            Text("VPN candidate \(snapshot.utun) · uplink \(snapshot.uplink)")
            Text("Unbound VPN peer: \(snapshot.defaultTCP)")
            Text("Bound VPN candidate: \(snapshot.utunTCP)")
            Text("Bound uplink: \(snapshot.uplinkTCP)")
            Text("Loopback: \(snapshot.loopbackTCP)")
            if let path = snapshot.nwConnectionPath { Text("NWConnection: \(path)") }
        }
        .font(.footnote.monospaced())
        .textSelection(.enabled)
    }

    var body: some View {
        Form {
            Section("NETWORK SNAPSHOT") {
                LabeledContent("System path", value: research.pathDescription)
                LabeledContent("VPN interface candidate", value: research.vpnInterfaceDescription)
                Text("Client interface 10.7.1.1 and developer endpoint 10.7.0.1 serve different roles. A visible utun does not verify VPN ownership or developer pairing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Network path interfaces", value: research.networkInterfacesDescription)
                    .font(.caption)
                Text(research.interfaceDescription)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Button("Refresh network snapshot") { research.refreshInterfaces() }
            }

            Section("v0.22 REMOTE PAIRING PORT — READ ONLY") {
                Text("49152 is a fallback, not a guaranteed iPhone Remote Pairing port. Discover the advertised _remotepairing._tcp service on Wi-Fi first, then save its real port for a fresh 5G-only test.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Saved connection port", value: String(TunnelConfig.targetPort))
                LabeledContent("Discovery status", value: research.discoveryStatus)
                    .font(.footnote)
                Button(research.discoveryRunning ? "Discovering…" : "Discover pairing service port") {
                    research.discoverRemotePairing()
                }
                .disabled(research.discoveryRunning)
                if !research.discoveredServices.isEmpty {
                    ForEach(research.discoveredServices) { service in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(service.name).font(.footnote.weight(.semibold))
                            Text("Port \(service.port) · \(service.host)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Button("Use port \(service.port) for next new session") {
                                TunnelConfig.setTargetPort(String(service.port))
                                portText = String(service.port)
                                research.generalNote = "Selected port \(service.port) for future new sessions. No GPS state changed. Confirm the discovered service belongs to this iPhone."
                            }
                            .disabled(!safeToProbe)
                        }
                    }
                }
                Text("Bonjour might be unavailable with Wi-Fi off, and discovered services could belong to other nearby devices. Do not change ports during a simulation. If discovery finds nothing, keep the currently working port.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("v0.22 5G-ONLY START AUDIT — NO GPS CHANGES") {
                Text("With Wi-Fi OFF in Settings, mobile data ON and LocalDevVPN connected, compare the paired protocol over the VPN peer and loopback. The same saved port is used for both. This does NOT start or clear a simulation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Network detected", value: research.pathDescription)
                LabeledContent("Test port", value: String(TunnelConfig.targetPort))
                VStack(alignment: .leading, spacing: 5) {
                    Text("VPN 10.7.0.1").font(.subheadline.weight(.semibold))
                    Text(research.cellularVPNResult)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Loopback 127.0.0.1").font(.subheadline.weight(.semibold))
                    Text(research.cellularLoopbackResult)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
                Button(research.cellularAuditRunning ? "Testing both routes…" : "Run paired VPN vs loopback audit") {
                    research.runCellularAudit(port: TunnelConfig.targetPort,
                                              pairingPath: pairing.pairingPath)
                }
                .disabled(!pairing.hasPairingFile || !safeToProbe || research.cellularAuditRunning || research.handshakeRunning)
                Text("If VPN fails but loopback TCP connects, this isolates a route/protocol problem; it does not prove any usable pairing tunnel. If both paired handshakes fail, Roam cannot start a new GPS session over that configuration. Do not repeatedly reset a working session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("v0.23 CELLULAR ROUTE COMPARISON — NO GPS CHANGES") {
                Text("Compare the same developer endpoint on Wi-Fi and cellular without changing the VPN, pairing file or simulated location. Run once on connected Wi-Fi, then once with Wi-Fi OFF in Settings. Results are saved locally for side-by-side review.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Current transport", value: research.pathDescription)
                LabeledContent("VPN interface candidate", value: research.selectedUtun.isEmpty ? "None visible" : research.labelForUtun(research.selectedUtun))
                    .font(.footnote)
                LabeledContent("Uplink probe interface", value: research.routeUplinkDescription)
                    .font(.footnote)
                LabeledContent("Target", value: "10.7.0.1:\(TunnelConfig.targetPort)")
                Button(research.routeAuditRunning ? "Testing local paths…" : "Capture this network's route audit") {
                    research.runRouteAudit(port: TunnelConfig.targetPort)
                }
                .disabled(!safeToProbe || research.routeAuditRunning || research.cellularAuditRunning || research.handshakeRunning || research.interfaceTestRunning)
                Text(research.routeAuditStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LabeledContent("System connection path", value: research.routeNWPathResult)
                    .font(.footnote)
                routeFinding("Unbound TCP → VPN peer", result: research.routeDefaultResult)
                routeFinding("Bound TCP → VPN candidate", result: research.routeUtunResult)
                routeFinding("Bound TCP → uplink", result: research.routeUplinkResult)
                routeFinding("Loopback TCP (control)", result: research.routeLoopbackResult)

                if let wifi = research.wifiRouteSnapshot {
                    routeSnapshot(wifi, title: "Saved Wi-Fi baseline")
                }
                if let cellular = research.cellularRouteSnapshot {
                    routeSnapshot(cellular, title: "Saved cellular baseline")
                }
                if let wifi = research.wifiRouteSnapshot, let cellular = research.cellularRouteSnapshot {
                    Text("Comparison: Wi-Fi VPN peer: \(wifi.defaultTCP). Cellular VPN peer: \(cellular.defaultTCP). These are socket outcomes, NOT a system routing-table dump or proof that packets reached LocalDevVPN.")
                        .font(.caption)
                        .textSelection(.enabled)
                }
                Button("Clear saved Wi-Fi and cellular snapshots", role: .destructive) {
                    research.clearRouteSnapshots()
                }
                .disabled(research.wifiRouteSnapshot == nil && research.cellularRouteSnapshot == nil)
                Text("Roam cannot inspect another app's Network Extension packet counters, its effective route table, or the owner of a utun interface. A bound socket test only probes interface selection; it does not change the developer engine route. Running this test never starts GPS spoofing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("TCP REACHABILITY — NO GPS CHANGES") {
                HStack {
                    Text("Test port")
                    Spacer()
                    TextField("49152", text: $portText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                }
                ForEach(endpoints, id: \.self) { host in
                    LabeledContent(host, value: research.tcpResults[host] ?? "Not tested")
                        .font(.footnote)
                }
                Button("Run all three TCP tests") {
                    if let port = UInt16(portText), port > 0 {
                        research.runTCPTests(port: port)
                    } else {
                        research.generalNote = "Enter a TCP port from 1 to 65535."
                    }
                }
                Text("A successful TCP connection does NOT establish that Apple's paired developer protocol works. A failed test may indicate routing, refusal, or a timeout.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("INTERFACE-BOUND TCP — NO GPS CHANGES") {
                Text("Compare an ordinary TCP socket with one explicitly bound to a selected utun interface. Neither test authenticates to the developer service or changes GPS. Binding here does NOT change the interface used by Roam's idevice engine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if research.utunInterfaces.isEmpty {
                    Text("No utun interface is visible to this app. Connect the original LocalDevVPN, then refresh the snapshot.")
                        .font(.footnote)
                } else {
                    Picker("Interface", selection: $research.selectedUtun) {
                        ForEach(research.utunInterfaces, id: \.self) { name in
                            Text(research.labelForUtun(name)).tag(name)
                        }
                    }
                }
                Picker("TCP target", selection: $comparisonHost) {
                    Text("VPN endpoint 10.7.0.1").tag("10.7.0.1")
                    Text("Loopback 127.0.0.1").tag("127.0.0.1")
                }
                LabeledContent("Comparison endpoint", value: research.boundEndpoint)
                    .font(.footnote)
                LabeledContent("Default TCP", value: research.unboundResult)
                    .font(.footnote)
                LabeledContent("Bound TCP", value: research.boundResult)
                    .font(.footnote)
                Button("Compare default vs interface-bound TCP") {
                    if let port = UInt16(portText), port > 0 {
                        research.runInterfaceBoundComparison(host: comparisonHost, port: port)
                    } else {
                        research.generalNote = "Enter a TCP port from 1 to 65535."
                    }
                }
                .disabled(research.utunInterfaces.isEmpty || research.interfaceTestRunning)
                Text("If the bound socket connects over 5G but default TCP does not, that supports an interface-selection hypothesis. It does NOT prove the developer handshake can use that route. Interface binding can fail under iOS policy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("PAIRED DEVELOPER HANDSHAKE — NO GPS CHANGES") {
                Picker("Endpoint", selection: $handshakeHost) {
                    Text("VPN 10.7.0.1").tag("10.7.0.1")
                    Text("Loopback 127.0.0.1").tag("127.0.0.1")
                }
                LabeledContent("Pairing file", value: pairing.hasPairingFile ? "Available" : "Missing")
                LabeledContent("Last probe", value: research.handshakeEndpoint)
                    .font(.footnote)
                LabeledContent("Handshake stage", value: research.handshakeStage)
                    .font(.footnote)
                Button("Attempt paired handshake") {
                    guard let port = UInt16(portText), port > 0 else {
                        research.handshakeResult = "Invalid port."
                        return
                    }
                    research.runPairedHandshake(host: handshakeHost,
                                                port: port,
                                                pairingPath: pairing.pairingPath)
                }
                .disabled(!pairing.hasPairingFile || research.handshakeRunning || !safeToProbe || research.cellularAuditRunning)
                Text(research.handshakeResult)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                Text("Stop any active spoofing session before this test. It tries to authenticate to the developer tunnel but does not call the GPS simulation APIs. This operation can take longer than a TCP test.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("COMPARISON") {
                Text("1. First test the existing Wi-Fi baseline, with no active spoofing, and optionally discover the advertised pairing port.\n2. Stop the simulation cleanly, turn Wi-Fi OFF in Settings, leave 4G/5G ON and connect LocalDevVPN.\n3. Run the paired VPN-vs-loopback audit using the saved port.\n4. Copy the diagnostic report, compare against the Wi-Fi result, and only then attempt a fresh teleport using an endpoint whose paired RSD handshake succeeded. Don't modify a working session.")
                    .font(.footnote)
                if !research.generalNote.isEmpty {
                    Text(research.generalNote).font(.footnote)
                }
                Button("Copy diagnostic report") {
                    UIPasteboard.general.string = research.report(port: portText)
                    research.generalNote = "Diagnostic report copied. The pairing file and GPS coordinates are not included."
                }
                Text("Local on-device testing only. Nothing is uploaded. Never share your pairing file. The report includes connection errors and interface addresses, so review it before sharing publicly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Cellular research")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { research.startMonitoring() }
        .onDisappear { research.stopMonitoring() }
    }
}

/// Only read-only route-test summaries; no pairing credentials or GPS coordinates.
private struct RoamRouteAuditSnapshot: Codable {
    let date: String
    let transport: String
    let port: UInt16
    let utun: String
    let uplink: String
    let defaultTCP: String
    let utunTCP: String
    let uplinkTCP: String
    let loopbackTCP: String
    let nwConnectionPath: String?
}

@MainActor
private final class CellularResearchModel: ObservableObject {
    @Published var pathDescription = "Checking…"
    @Published var discoveredServices: [RoamDiscoveredService] = []
    @Published var discoveryStatus = "Not run"
    @Published var discoveryRunning = false
    @Published var cellularVPNResult = "Not tested"
    @Published var cellularLoopbackResult = "Not tested"
    @Published var cellularAuditRunning = false
    @Published var routeAuditRunning = false
    @Published var routeAuditStatus = "Not run. Stop simulation before testing."
    @Published var routeDefaultResult = "Not tested"
    @Published var routeUtunResult = "Not tested"
    @Published var routeUplinkResult = "Not tested"
    @Published var routeLoopbackResult = "Not tested"
    @Published var routeNWPathResult = "Not tested"
    @Published var wifiRouteSnapshot: RoamRouteAuditSnapshot?
    @Published var cellularRouteSnapshot: RoamRouteAuditSnapshot?
    private var routeNWConnection: NWConnection?
    private var routeUplink = ""
    var routeUplinkDescription: String {
        switch pathDescription {
        case let s where s.contains("Cellular"): return "pdp_ip0 (candidate; not verified)"
        case let s where s.contains("Wi-Fi"): return "en0 (candidate; not verified)"
        default: return "Transport not established"
        }
    }
    private static let wifiSnapshotKey = "roam.route.v023.wifi"
    private static let cellularSnapshotKey = "roam.route.v023.cellular"

    private var discovery: RoamRemotePairingBrowser?
    private var lastCellularAuditTime = "Not tested"
    @Published var interfaceDescription = "Checking…"
    @Published var tcpResults: [String: String] = [:]
    @Published var handshakeResult = "Not tested"
    @Published var handshakeRunning = false
    @Published var handshakeStage = "Not tested"
    @Published var handshakeEndpoint = "Not tested"
    @Published var generalNote = ""
    @Published var networkInterfacesDescription = "Checking…"
    @Published var vpnInterfaceDescription = "Checking…"
    @Published var utunInterfaces: [String] = []
    @Published var selectedUtun = ""
    @Published var unboundResult = "Not tested"
    @Published var boundResult = "Not tested"
    @Published var boundEndpoint = "Not tested"
    @Published var interfaceTestRunning = false

    private var utunAddresses: [String: [String]] = [:]
    private var lastInterfaceTestTime = "Not tested"
    private var lastHandshakeTime = "Not tested"
    private var monitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "roam.research.path")
    private let tcpQueue = DispatchQueue(label: "roam.research.tcp")
    private var connections: [String: NWConnection] = [:]
    private var lastTCPTime = "Not tested"

    func startMonitoring() {
        if let data = UserDefaults.standard.data(forKey: Self.wifiSnapshotKey) {
            wifiRouteSnapshot = try? JSONDecoder().decode(RoamRouteAuditSnapshot.self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: Self.cellularSnapshotKey) {
            cellularRouteSnapshot = try? JSONDecoder().decode(RoamRouteAuditSnapshot.self, from: data)
        }
        refreshInterfaces()
        let pathMonitor = NWPathMonitor()
        monitor = pathMonitor
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let status: String
            switch path.status {
            case .satisfied:
                if path.usesInterfaceType(.wifi) { status = "Satisfied · Wi-Fi" }
                else if path.usesInterfaceType(.cellular) { status = "Satisfied · Cellular" }
                else { status = "Satisfied · Other interface" }
            case .unsatisfied: status = "Unsatisfied"
            case .requiresConnection: status = "Requires connection"
            @unknown default: status = "Unknown"
            }
            DispatchQueue.main.async {
                self?.pathDescription = status
                self?.networkInterfacesDescription = path.availableInterfaces.isEmpty
                    ? "None exposed by system path"
                    : path.availableInterfaces.map { "\($0.name) (\($0.type))" }.joined(separator: ", ")
                self?.refreshInterfaces()
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    func stopMonitoring() {
        routeNWConnection?.cancel()
        routeNWConnection = nil
        discovery?.stop()
        discovery = nil
        discoveryRunning = false
        monitor?.cancel()
        monitor = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
    }

    func refreshInterfaces() {
        var start: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&start) == 0, let first = start else {
            interfaceDescription = "getifaddrs failed"
            return
        }
        defer { freeifaddrs(start) }
        var items = Set<String>()
        var vpnCandidates = [String: [String]]()
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let item = current.pointee
            let name = String(cString: item.ifa_name)
            if name.hasPrefix("utun") && vpnCandidates[name] == nil {
                vpnCandidates[name] = []
            }
            if let addr = item.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_INET) {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr,
                               socklen_t(MemoryLayout<sockaddr_in>.size),
                               &buffer, socklen_t(buffer.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: buffer)
                    let index = name.withCString { if_nametoindex($0) }
                    items.insert("\(name) [if#\(index)]: \(ip)")
                    if name.hasPrefix("utun") {
                        vpnCandidates[name, default: []].append(ip)
                    }
                }
            }
            cursor = item.ifa_next
        }
        interfaceDescription = items.sorted().joined(separator: "\n")
        utunAddresses = vpnCandidates
        utunInterfaces = vpnCandidates.keys.sorted()
        // Prefer the observed LocalDevVPN tunnel address, 10.7.1.1, without
        // assuming other utun interfaces are necessarily LocalDevVPN.
        let candidate = utunInterfaces.first { vpnCandidates[$0]?.contains("10.7.1.1") == true }
        if !utunInterfaces.contains(selectedUtun) {
            selectedUtun = candidate ?? utunInterfaces.first ?? ""
        }
        if let candidate {
            vpnInterfaceDescription = "10.7.1.1 on \(candidate) (not authenticated)"
        } else {
            vpnInterfaceDescription = "10.7.1.1 not seen (not proof VPN is off)"
        }
    }

    func labelForUtun(_ name: String) -> String {
        let addresses = utunAddresses[name] ?? []
        return addresses.isEmpty ? name : "\(name) — \(addresses.joined(separator: ", "))"
    }

    func clearRouteSnapshots() {
        wifiRouteSnapshot = nil
        cellularRouteSnapshot = nil
        UserDefaults.standard.removeObject(forKey: Self.wifiSnapshotKey)
        UserDefaults.standard.removeObject(forKey: Self.cellularSnapshotKey)
        routeAuditStatus = "Stored route comparisons cleared. GPS and pairing unchanged."
    }

    func runRouteAudit(port: UInt16) {
        guard !routeAuditRunning else { return }
        let transport: String
        let uplink: String
        if pathDescription.contains("Wi-Fi") {
            transport = "Wi-Fi"
            uplink = "en0"
        } else if pathDescription.contains("Cellular") {
            transport = "Cellular"
            uplink = "pdp_ip0"
        } else {
            routeAuditStatus = "Network not ready. Connect Wi-Fi or cellular and refresh."
            return
        }
        // Prefer the observed tunnel-client IP rather than assuming the
        // user's last manually selected utun still belongs to LocalDevVPN.
        let candidate = utunInterfaces.first { utunAddresses[$0]?.contains("10.7.1.1") == true }
            ?? selectedUtun
        routeAuditRunning = true
        routeAuditStatus = "Checking VPN endpoint via unbound, utun-bound and uplink-bound sockets…"
        routeDefaultResult = "Testing…"
        routeUtunResult = "Queued…"
        routeUplinkResult = "Queued…"
        routeLoopbackResult = "Queued…"
        routeNWPathResult = "Inspecting NWConnection path (does not reveal VPN packet counters)…"
        routeUplink = uplink
        recordNWConnectionPath(port: port)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let defaultTCP = RoamBoundTCPProbe.checkDetailed(host: "10.7.0.1", port: port, interface: nil)
            DispatchQueue.main.async { self?.routeDefaultResult = defaultTCP }
            let candidateResult = candidate.isEmpty
                ? "No utun candidate visible"
                : RoamBoundTCPProbe.checkDetailed(host: "10.7.0.1", port: port, interface: candidate)
            DispatchQueue.main.async { self?.routeUtunResult = candidateResult }
            let uplinkResult = RoamBoundTCPProbe.checkDetailed(host: "10.7.0.1", port: port, interface: uplink)
            DispatchQueue.main.async { self?.routeUplinkResult = uplinkResult }
            let loopbackResult = RoamBoundTCPProbe.checkDetailed(host: "127.0.0.1", port: port, interface: nil)
            DispatchQueue.main.async {
                guard let self else { return }
                let result = RoamRouteAuditSnapshot(
                    date: ISO8601DateFormatter().string(from: Date()),
                    transport: transport, port: port,
                    utun: candidate.isEmpty ? "none" : candidate,
                    uplink: uplink,
                    defaultTCP: defaultTCP, utunTCP: candidateResult,
                    uplinkTCP: uplinkResult, loopbackTCP: loopbackResult,
                    nwConnectionPath: self.routeNWPathResult)
                self.routeLoopbackResult = loopbackResult
                self.routeAuditRunning = false
                self.routeAuditStatus = "\(transport) snapshot saved. No GPS or VPN configuration changed."
                if let data = try? JSONEncoder().encode(result) {
                    if transport == "Wi-Fi" {
                        self.wifiRouteSnapshot = result
                        UserDefaults.standard.set(data, forKey: Self.wifiSnapshotKey)
                    } else {
                        self.cellularRouteSnapshot = result
                        UserDefaults.standard.set(data, forKey: Self.cellularSnapshotKey)
                    }
                }
            }
        }
    }

    /// Current connection path is observable from Network.framework; it is
    /// not a kernel routing table and cannot identify another VPN app's packets.
    private func recordNWConnectionPath(port: UInt16) {
        routeNWConnection?.cancel()
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            routeNWPathResult = "Invalid port"
            return
        }
        let conn = NWConnection(host: "10.7.0.1", port: endpointPort, using: .tcp)
        routeNWConnection = conn
        conn.pathUpdateHandler = { [weak self] path in
            let label = Self.describe(path: path)
            DispatchQueue.main.async {
                guard let self, self.routeNWConnection === conn else { return }
                self.routeNWPathResult = "NWPath: \(label) (available interfaces are not proof of selected VPN route)"
            }
        }
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready, .failed(_):
                let outcome: String
                switch state {
                case .ready: outcome = "TCP connected"
                case .failed(let error): outcome = "TCP failed: \(error.localizedDescription)"
                default: outcome = "Unknown"
                }
                let path = conn.currentPath.map { Self.describe(path: $0) } ?? "path unavailable"
                DispatchQueue.main.async {
                    guard let self, self.routeNWConnection === conn else { return }
                    self.routeNWPathResult = "\(outcome); NWPath: \(path) (not the kernel route table)"
                    self.routeNWConnection = nil
                    conn.cancel()
                }
            default: break
            }
        }
        conn.start(queue: tcpQueue)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.routeNWConnection === conn else { return }
            self.routeNWPathResult += "; observation timed out after 6s"
            self.routeNWConnection = nil
            conn.cancel()
        }
    }

    private nonisolated static func describe(path: NWPath) -> String {
        let status: String
        switch path.status {
        case .satisfied: status = "satisfied"
        case .unsatisfied: status = "unsatisfied"
        case .requiresConnection: status = "requires connection"
        @unknown default: status = "unknown"
        }
        let types = ["Wi-Fi", "Cellular", "Wired", "Other"]
        let active = [path.usesInterfaceType(.wifi), path.usesInterfaceType(.cellular),
                      path.usesInterfaceType(.wiredEthernet), path.usesInterfaceType(.other)]
        let names = zip(types, active).compactMap { $0.1 ? $0.0 : nil }.joined(separator: ", ")
        let available = path.availableInterfaces.map { $0.name }.joined(separator: ", ")
        return "\(status), uses [\(names)], available [\(available)]"
    }

    func discoverRemotePairing() {
        discovery?.stop()
        discoveredServices = []
        discoveryStatus = "Browsing local Bonjour (up to 6 seconds)…"
        discoveryRunning = true
        let browser = RoamRemotePairingBrowser()
        discovery = browser
        browser.start(timeout: 6) { [weak self, weak browser] services, note in
            guard let self, self.discovery === browser else { return }
            self.discoveredServices = services
            self.discoveryStatus = note
            self.discoveryRunning = false
            self.discovery = nil
        }
    }

    func runCellularAudit(port: UInt16, pairingPath: String) {
        cellularAuditRunning = true
        cellularVPNResult = "Testing…"
        cellularLoopbackResult = "Queued…"
        lastCellularAuditTime = ISO8601DateFormatter().string(from: Date())
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for host in ["10.7.0.1", "127.0.0.1"] {
                let tcp = RoamBoundTCPProbe.check(host: host, port: port, interface: nil)
                let start = ProcessInfo.processInfo.systemUptime
                let outcome = RoamPairingHandshakeProbe.check(host: host, port: port,
                                                              pairingPath: pairingPath)
                let seconds = ProcessInfo.processInfo.systemUptime - start
                let result = "TCP: \(tcp); paired: \(outcome.stage) — \(outcome.detail) (\(String(format: "%.1f", seconds))s)"
                DispatchQueue.main.async {
                    if host == "10.7.0.1" {
                        self?.cellularVPNResult = result
                        self?.cellularLoopbackResult = "Testing…"
                    } else {
                        self?.cellularLoopbackResult = result
                        self?.cellularAuditRunning = false
                    }
                }
            }
        }
    }

    func runInterfaceBoundComparison(host: String, port: UInt16) {
        let interface = selectedUtun
        guard !interface.isEmpty, utunInterfaces.contains(interface) else {
            boundResult = "Select an available utun interface."
            return
        }
        interfaceTestRunning = true
        unboundResult = "Testing…"
        boundResult = "Testing…"
        lastInterfaceTestTime = ISO8601DateFormatter().string(from: Date())
        boundEndpoint = "\(host):\(port) on \(interface)"
        // Both probes use the SAME BSD socket implementation to ensure the
        // interface option is the only intentional difference between tests.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let normal = RoamBoundTCPProbe.check(host: host, port: port, interface: nil)
            DispatchQueue.main.async { self?.unboundResult = normal }
            let bound = RoamBoundTCPProbe.check(host: host, port: port, interface: interface)
            DispatchQueue.main.async {
                self?.boundResult = bound
                self?.interfaceTestRunning = false
            }
        }
    }

    func runTCPTests(port: UInt16) {
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        lastTCPTime = ISO8601DateFormatter().string(from: Date())
        generalNote = ""
        for host in ["10.7.0.1", "127.0.0.1", "::1"] {
            tcpResults[host] = "Testing…"
            guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
                tcpResults[host] = "Invalid port"
                continue
            }
            let connection = NWConnection(host: NWEndpoint.Host(host),
                                          port: endpointPort,
                                          using: .tcp)
            connections[host] = connection
            connection.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    guard let self,
                          self.connections[host] === connection else { return }
                    switch state {
                    case .ready:
                        self.tcpResults[host] = "TCP connected"
                        self.connections.removeValue(forKey: host)
                        connection.cancel()
                    case .failed(let error):
                        self.tcpResults[host] = "Failed: \(error.localizedDescription)"
                        self.connections.removeValue(forKey: host)
                        connection.cancel()
                    default: break
                    }
                }
            }
            connection.start(queue: tcpQueue)
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self,
                      self.connections[host] === connection else { return }
                self.tcpResults[host] = "Timed out after 6 seconds"
                self.connections.removeValue(forKey: host)
                connection.cancel()
            }
        }
    }

    func runPairedHandshake(host: String, port: UInt16, pairingPath: String) {
        handshakeRunning = true
        handshakeResult = "Connecting to \(host):\(port)…"
        handshakeStage = "Starting paired tunnel"
        handshakeEndpoint = "\(host):\(port)"
        lastHandshakeTime = ISO8601DateFormatter().string(from: Date())
        // Never invoke the GPS injection engine. This is a separate adapter/handshake.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = RoamPairingHandshakeProbe.check(host: host,
                                                         port: port,
                                                         pairingPath: pairingPath)
            DispatchQueue.main.async {
                self?.handshakeResult = outcome.detail
                self?.handshakeStage = outcome.stage
                self?.handshakeRunning = false
            }
        }
    }

    func report(port: String) -> String {
        var lines = [
            "Roam v0.23 cellular route and startup audit — \(ISO8601DateFormatter().string(from: Date()))",
            "Device network path: \(pathDescription)",
            "Interfaces:\n\(interfaceDescription)",
            "Network path available interfaces: \(networkInterfacesDescription)",
            "VPN candidate: \(vpnInterfaceDescription)",
            "TCP port: \(port); last tests: \(lastTCPTime)",
        ]
        for host in ["10.7.0.1", "127.0.0.1", "::1"] {
            lines.append("\(host): \(tcpResults[host] ?? "Not tested")")
        }
        lines.append("Interface-bound test: \(lastInterfaceTestTime) / \(boundEndpoint)")
        lines.append("BSD default TCP: \(unboundResult)")
        lines.append("BSD bound TCP: \(boundResult)")
        lines.append("Paired attempt: \(lastHandshakeTime) / \(handshakeEndpoint)")
        lines.append("Paired stage: \(handshakeStage)")
        lines.append("Paired result: \(handshakeResult)")
        lines.append("Configured pairing port for new sessions: \(TunnelConfig.targetPort)")
        lines.append("Bonjour discovery: \(discoveryStatus)")
        for service in discoveredServices { lines.append("Bonjour service: \(service.name) / \(service.host) / \(service.port)") }
        lines.append("Cellular A/B attempt: \(lastCellularAuditTime)")
        lines.append("VPN paired result: \(cellularVPNResult)")
        lines.append("Loopback paired result: \(cellularLoopbackResult)")
        lines.append("v0.23 route A/B: \(routeAuditStatus)")
        lines.append("Observed NWConnection path: \(routeNWPathResult)")
        lines.append("Unbound VPN peer: \(routeDefaultResult)")
        lines.append("Utun-bound VPN peer: \(routeUtunResult)")
        lines.append("Uplink-bound VPN peer: \(routeUplinkResult)")
        lines.append("Loopback control: \(routeLoopbackResult)")
        if let wifi = wifiRouteSnapshot {
            lines.append("Saved Wi-Fi snapshot: \(wifi.date); target port \(wifi.port), utun=\(wifi.utun), uplink=\(wifi.uplink), unbound=\(wifi.defaultTCP), utun bound=\(wifi.utunTCP), uplink bound=\(wifi.uplinkTCP), loopback=\(wifi.loopbackTCP), NWPath=\(wifi.nwConnectionPath ?? "not recorded")")
        }
        if let cellular = cellularRouteSnapshot {
            lines.append("Saved cellular snapshot: \(cellular.date); target port \(cellular.port), utun=\(cellular.utun), uplink=\(cellular.uplink), unbound=\(cellular.defaultTCP), utun bound=\(cellular.utunTCP), uplink bound=\(cellular.uplinkTCP), loopback=\(cellular.loopbackTCP), NWPath=\(cellular.nwConnectionPath ?? "not recorded")")
        }
        lines.append("Limitations: Roam cannot read another app's Network Extension packet counters, VPN configuration or actual kernel routing table; NWPath and bound sockets supply limited observations only.")
        lines.append("Interpretation: TCP and a matching utun IP do not prove developer service access or VPN ownership. A Bonjour service may belong to another device. No GPS commands are sent during these probes.")
        return lines.joined(separator: "\n")
    }
}

/// Independent libidevice probe: verify remote pairing and RemoteXPC/RSD only.
/// Read-only; never starts or clears a location simulation session.
private struct RoamHandshakeOutcome {
    let stage: String
    let detail: String
}

private enum RoamPairingHandshakeProbe {
    static func check(host: String, port: UInt16, pairingPath: String) -> RoamHandshakeOutcome {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        guard host.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else {
            return RoamHandshakeOutcome(stage: "Endpoint validation", detail: "Only IPv4 addresses are supported for the paired handshake.")
        }

        var pairingFile: OpaquePointer?
        if let error = pairingPath.withCString({ rp_pairing_file_read($0, &pairingFile) }) {
            return takeError(error, stage: "Read pairing file")
        }
        guard let pairingFile else { return RoamHandshakeOutcome(stage: "Pairing read", detail: "Pairing file returned no handle.") }
        defer { rp_pairing_file_free(pairingFile) }

        var adapter: OpaquePointer?
        var handshake: OpaquePointer?
        defer {
            if let handshake { rsd_handshake_free(handshake) }
            if let adapter { adapter_free(adapter) }
        }
        let error = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                tunnel_create_rppairing($0,
                                        socklen_t(MemoryLayout<sockaddr_in>.stride),
                                        "RoamCellularResearch",
                                        pairingFile,
                                        nil, nil,
                                        &adapter, &handshake)
            }
        }
        if let error { return takeError(error, stage: "Paired tunnel") }
        guard let adapter, let handshake else { return RoamHandshakeOutcome(stage: "RPPairing tunnel", detail: "Paired tunnel returned missing handles.") }

        var server: OpaquePointer?
        if let error = remote_server_connect_rsd(adapter, handshake, &server) {
            if let server { remote_server_free(server) }
            return takeError(error, stage: "RemoteXPC/RSD")
        }
        if let server { remote_server_free(server) }
        return RoamHandshakeOutcome(stage: "RSD connected", detail: "SUCCESS: Paired tunnel and RSD connected (GPS not modified).")
    }

    private static func takeError(_ error: UnsafeMutablePointer<IdeviceFfiError>, stage: String) -> RoamHandshakeOutcome {
        let code = error.pointee.code
        let sub = error.pointee.sub_code
        let message = error.pointee.message.map { String(cString: $0) } ?? "Unspecified error"
        idevice_error_free(error)
        return RoamHandshakeOutcome(stage: stage, detail: "\(stage) failed [\(code)/\(sub)]: \(message)")
    }
}

/// Compare BSD TCP connections with and without IP_BOUND_IF (Darwin socket
/// option 25). This does NOT alter the idevice FFI connection or any VPN route.
/// All operations are made on a background queue and time out after 5 seconds.
private enum RoamBoundTCPProbe {
    static func check(host: String, port: UInt16, interface: String?) -> String {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return "socket failed: \(explain(errno))" }
        defer { _ = Darwin.close(fd) }

        if let interface {
            let index = interface.withCString { if_nametoindex($0) }
            guard index != 0 else { return "Interface \(interface) not found" }
            var boundIfIndex = Int32(index)
            // Darwin's IP_BOUND_IF = 25. If iOS rejects the binding, preserve
            // and report its exact errno rather than retrying on cellular.
            let result = withUnsafePointer(to: &boundIfIndex) { pointer in
                setsockopt(fd, IPPROTO_IP, 25, pointer,
                           socklen_t(MemoryLayout<Int32>.size))
            }
            guard result == 0 else {
                return "IP_BOUND_IF \(interface) failed: \(explain(errno))"
            }
        }

        let oldFlags = fcntl(fd, F_GETFL, 0)
        guard oldFlags >= 0 && fcntl(fd, F_SETFL, oldFlags | O_NONBLOCK) == 0 else {
            return "Nonblocking setup failed: \(explain(errno))"
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        guard host.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else {
            return "Invalid IPv4 endpoint"
        }

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connectResult == 0 { return "TCP connected" }
        let connectError = errno
        guard connectError == EINPROGRESS else {
            return "connect failed: \(explain(connectError))"
        }

        var event = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let waitResult = Darwin.poll(&event, 1, 5_000)
        if waitResult == 0 { return "Timed out after 5 seconds" }
        if waitResult < 0 { return "poll failed: \(explain(errno))" }

        var socketError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        let optionResult = withUnsafeMutablePointer(to: &socketError) { pointer in
            getsockopt(fd, SOL_SOCKET, SO_ERROR, pointer, &length)
        }
        guard optionResult == 0 else { return "SO_ERROR failed: \(explain(errno))" }
        return socketError == 0 ? "TCP connected" : "connect failed: \(explain(socketError))"
    }

    /// Same target as the previous audit but adds the selected local TCP
    /// source endpoint on success. A refused socket can't establish a route.
    static func checkDetailed(host: String, port: UInt16, interface: String?) -> String {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return "socket failed: \(explain(errno))" }
        defer { _ = Darwin.close(fd) }
        if let interface {
            let index = interface.withCString { if_nametoindex($0) }
            guard index > 0 else { return "Interface \(interface) not found on this snapshot" }
            var boundIfIndex = Int32(index)
            let rc = withUnsafePointer(to: &boundIfIndex) {
                setsockopt(fd, IPPROTO_IP, 25, $0, socklen_t(MemoryLayout<Int32>.size))
            }
            guard rc == 0 else { return "IP_BOUND_IF \(interface) failed: \(explain(errno))" }
        }
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0 && fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
            return "Nonblocking setup failed: \(explain(errno))"
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        guard host.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else {
            return "Invalid IPv4 endpoint"
        }
        let connected = withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connected != 0 {
            let initialError = errno
            guard initialError == EINPROGRESS else {
                return "connect failed: \(explain(initialError))"
            }
            var event = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let waitResult = Darwin.poll(&event, 1, 5_000)
            if waitResult == 0 { return "Timed out after 5 seconds" }
            if waitResult < 0 { return "poll failed: \(explain(errno))" }
            var code: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            let rc = withUnsafeMutablePointer(to: &code) {
                getsockopt(fd, SOL_SOCKET, SO_ERROR, $0, &length)
            }
            guard rc == 0 else { return "SO_ERROR failed: \(explain(errno))" }
            if code != 0 { return "connect failed: \(explain(code))" }
        }
        var local = sockaddr_in()
        var localSize = socklen_t(MemoryLayout<sockaddr_in>.size)
        let localResult = withUnsafeMutablePointer(to: &local) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &localSize)
            }
        }
        guard localResult == 0 else { return "TCP connected; local endpoint unavailable: \(explain(errno))" }
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let resolve = withUnsafePointer(to: &local) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, localSize, &hostBuffer, socklen_t(hostBuffer.count),
                            nil, 0, NI_NUMERICHOST)
            }
        }
        guard resolve == 0 else { return "TCP connected; local address unavailable" }
        return "TCP connected, local socket \(String(cString: hostBuffer)):\(UInt16(bigEndian: local.sin_port))"
    }

    private static func explain(_ code: Int32) -> String {
        "\(String(cString: strerror(code))) (errno \(code))"
    }
}


// v0.22: Discover the actual _remotepairing._tcp port rather than assuming
// the service always listens on 49152. Detection is non-destructive.
// No selection is automatically applied; nearby devices may advertise too.
private struct RoamDiscoveredService: Identifiable, Hashable {
    let name: String
    let host: String
    let port: Int
    var id: String { "\(name)|\(host)|\(port)" }
}

private final class RoamRemotePairingBrowser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var found: [RoamDiscoveredService] = []
    private var finished = false
    private var onComplete: (([RoamDiscoveredService], String) -> Void)?

    func start(timeout: TimeInterval, onComplete: @escaping ([RoamDiscoveredService], String) -> Void) {
        self.onComplete = onComplete
        browser.delegate = self
        browser.schedule(in: .main, forMode: .common)
        browser.searchForServices(ofType: "_remotepairing._tcp.", inDomain: "local.")
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, !self.finished else { return }
            self.finish(note: self.found.isEmpty
                        ? "No service advertised (not proof the service is absent)"
                        : "Found \(self.found.count) advertised service(s); verify the device name")
        }
    }

    func stop() {
        guard !finished else { return }
        finish(note: "Stopped")
    }

    private func finish(note: String) {
        guard !finished else { return }
        finished = true
        browser.stop()
        for service in services { service.stop() }
        let completion = onComplete
        onComplete = nil
        completion?(found, note)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 4)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        finish(note: "Bonjour browse failed: \(errorDict)")
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard (1...65535).contains(sender.port) else { return }
        let result = RoamDiscoveredService(name: sender.name,
                                           host: sender.hostName ?? "unknown host",
                                           port: sender.port)
        if !found.contains(result) { found.append(result) }
        // Allow the discovery window to complete; another nearby device may
        // be advertising a different port. Do not guess which is this iPhone.
    }
}
