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
    @State private var portText = "49152"
    @State private var handshakeHost = "10.7.0.1"

    private let endpoints = ["10.7.0.1", "127.0.0.1", "::1"]

    var body: some View {
        Form {
            Section("NETWORK SNAPSHOT") {
                LabeledContent("System path", value: research.pathDescription)
                LabeledContent("VPN indication", value: LocalDevVPN.isConnected ? "Interface detected" : "No matching interface")
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

            Section("PAIRED DEVELOPER HANDSHAKE — NO GPS CHANGES") {
                Picker("Endpoint", selection: $handshakeHost) {
                    Text("VPN 10.7.0.1").tag("10.7.0.1")
                    Text("Loopback 127.0.0.1").tag("127.0.0.1")
                }
                LabeledContent("Pairing file", value: pairing.hasPairingFile ? "Available" : "Missing")
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
                Text("1. With Wi-Fi ON and LocalDevVPN connected, run TCP tests.\n2. Turn Wi-Fi OFF in Settings, leave 4G/5G and LocalDevVPN ON, and run them again.\n3. Compare error messages and try the paired handshake only when not spoofing.")
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
    @Published var generalNote = ""

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
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let item = current.pointee
            if let addr = item.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_INET) {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr,
                               socklen_t(MemoryLayout<sockaddr_in>.size),
                               &buffer, socklen_t(buffer.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    let name = String(cString: item.ifa_name)
                    // Device IPs only: no GPS data, credentials, or certificates.
                    let ip = String(cString: buffer)
                    items.insert("\(name): \(ip)")
                }
            }
            cursor = item.ifa_next
        }
        interfaceDescription = items.sorted().joined(separator: "\n")
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
        // Never invoke the GPS injection engine. This is a separate adapter/handshake.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let message = RoamPairingHandshakeProbe.check(host: host,
                                                         port: port,
                                                         pairingPath: pairingPath)
            DispatchQueue.main.async {
                self?.handshakeResult = message
                self?.handshakeRunning = false
            }
        }
    }

    func report(port: String) -> String {
        var lines = [
            "Roam v0.8 cellular research — \(ISO8601DateFormatter().string(from: Date()))",
            "Device network path: \(pathDescription)",
            "Interfaces:\n\(interfaceDescription)",
            "TCP port: \(port); last tests: \(lastTCPTime)",
        ]
        for host in ["10.7.0.1", "127.0.0.1", "::1"] {
            lines.append("\(host): \(tcpResults[host] ?? "Not tested")")
        }
        lines.append("Paired tunnel: \(handshakeResult)")
        return lines.joined(separator: "\n")
    }
}

/// Independent libidevice probe: verify remote pairing and RemoteXPC/RSD only.
/// Read-only; never starts or clears a location simulation session.
private enum RoamPairingHandshakeProbe {
    static func check(host: String, port: UInt16, pairingPath: String) -> String {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        guard host.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else {
            return "Only IPv4 addresses are supported for the paired handshake."
        }

        var pairingFile: OpaquePointer?
        if let error = pairingPath.withCString({ rp_pairing_file_read($0, &pairingFile) }) {
            return takeError(error, stage: "Read pairing file")
        }
        guard let pairingFile else { return "Pairing file returned no handle." }
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
        guard let adapter, let handshake else { return "Paired tunnel returned missing handles." }

        var server: OpaquePointer?
        if let error = remote_server_connect_rsd(adapter, handshake, &server) {
            if let server { remote_server_free(server) }
            return takeError(error, stage: "RemoteXPC/RSD")
        }
        if let server { remote_server_free(server) }
        return "SUCCESS: Paired tunnel and RSD connected (GPS not modified)."
    }

    private static func takeError(_ error: UnsafeMutablePointer<IdeviceFfiError>, stage: String) -> String {
        let code = error.pointee.code
        let sub = error.pointee.sub_code
        let message = error.pointee.message.map { String(cString: $0) } ?? "Unspecified error"
        idevice_error_free(error)
        return "\(stage) failed [\(code)/\(sub)]: \(message)"
    }
}
