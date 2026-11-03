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
                .disabled(!pairing.hasPairingFile || research.handshakeRunning || session.isSpoofing)
                Text(research.handshakeResult)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                Text("Stop any active spoofing session before this test. It tries to authenticate to the developer tunnel but does not call the GPS simulation APIs. This operation can take longer than a TCP test.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("COMPARISON") {
                Text("1. Confirm LocalDevVPN is connected in iOS Settings > VPN. Record the 10.7.1.1 client interface, if visible.\n2. With Wi-Fi OFF and mobile data OFF, run TCP reachability and default/bound tests, recording the selected endpoint and port.\n3. Turn mobile data ON (Wi-Fi still OFF) without reconnecting the VPN. Repeat the same tests.\n4. If no simulation is active, attempt the paired handshake. A TCP connection alone does not confirm a developer service.")
                    .font(.footnote)
                if !research.generalNote.isEmpty {
                    Text(research.generalNote).font(.footnote)
                }
                Button("Copy diagnostic report") {
                    UIPasteboard.general.string = research.report(port: portText)
                    research.generalNote = "Diagnostic report copied. The pairing file and GPS coordinates are not included."
                }
                Text("Local on-device testing only. Nothing is uploaded. The report includes connection errors and interface addresses, so review it before sharing publicly.")
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

@MainActor
private final class CellularResearchModel: ObservableObject {
    @Published var pathDescription = "Checking…"
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
            "Roam v0.12 cellular research — \(ISO8601DateFormatter().string(from: Date()))",
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
        lines.append("Interpretation: TCP and a matching utun IP do not prove developer service access or VPN ownership.")
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

    private static func explain(_ code: Int32) -> String {
        "\(String(cString: strerror(code))) (errno \(code))"
    }
}
