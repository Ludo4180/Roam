import Foundation
import idevice

enum LocationEngineError: LocalizedError {
    case invalidIP
    case pairingRead
    case tunnelCreate
    case remoteServer
    case simulationCreate
    case locationSet
    case locationClear
    case notActive

    var errorDescription: String? {
        switch self {
        case .invalidIP: return "Tunnel IP is invalid. Check Settings → Tunnel IP (usually 10.7.0.1)."
        case .pairingRead: return "Could not read the RPPairing file. Generate one with idevice_pair in RPPairing mode."
        case .tunnelCreate: return "Could not open the developer tunnel. Check LocalDevVPN; starting a new session may require Wi-Fi."
        case .remoteServer: return "Connected to the tunnel but RemoteXPC handshake failed."
        case .simulationCreate: return "Could not open Apple’s location simulation service."
        case .locationSet: return "Failed to set simulated coordinates."
        case .locationClear: return "Failed to clear simulated location."
        case .notActive: return "No active simulation session."
        }
    }

    static func from(code: Int32) -> LocationEngineError {
        switch code {
        case 1: return .invalidIP
        case 2: return .pairingRead
        case 3: return .tunnelCreate
        case 9: return .remoteServer
        case 10: return .simulationCreate
        case 11: return .locationSet
        case 12: return .locationClear
        default: return .locationSet
        }
    }
}

/// Thin Swift wrapper around idevice’s DVT location simulation (injects into locationd).
enum LocationEngine {
    private static let queue = DispatchQueue(label: "com.chrismack.locus.location", qos: .userInitiated)

    private static var adapter: OpaquePointer?
    private static var handshake: OpaquePointer?
    private static var remoteServer: OpaquePointer?
    private static var locationSimulation: OpaquePointer?

    private static let ok: Int32 = 0
    private static let invalidIP: Int32 = 1
    private static let pairingRead: Int32 = 2
    private static let tunnelCreate: Int32 = 3
    private static let remoteServerCode: Int32 = 9
    private static let simulationCreate: Int32 = 10
    private static let locationSet: Int32 = 11
    private static let locationClear: Int32 = 12

    // Diagnostic only: this reflects a retained handle, not proof of a live service.
    static var isSessionActive: Bool { locationSimulation != nil }
    private(set) static var lastStage = "not started"
    private(set) static var lastFailure = "none"
    private static func fail(_ stage: String, _ code: Int32, detail: String? = nil) -> Int32 {
        lastStage = stage
        if let detail {
            lastFailure = "\(stage) [\(code)]: \(detail)"
        } else {
            lastFailure = "\(stage) (code \(code))"
        }
        return code
    }

    /// Capture the underlying idevice FFI error before releasing it. In v0.11
    /// only the generic stage was exposed, obscuring whether transport,
    /// pairing, or RSD was responsible for a failure.
    private static func failFFI(_ error: UnsafeMutablePointer<IdeviceFfiError>,
                                stage: String, code: Int32, pairingPath: String = "") -> Int32 {
        let ffiCode = error.pointee.code
        let subCode = error.pointee.sub_code
        var message = error.pointee.message.map { String(cString: $0) } ?? "No detail"
        if !pairingPath.isEmpty {
            message = message.replacingOccurrences(of: pairingPath, with: "[pairing file]")
        }
        idevice_error_free(error)
        return fail(stage, code, detail: "idevice [\(ffiCode)/\(subCode)] \(message)")
    }

    static func set(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String) -> Result<Void, LocationEngineError> {
        var result: Result<Void, LocationEngineError> = .failure(.locationSet)
        queue.sync {
            let code = setLocked(latitude: latitude, longitude: longitude, pairingPath: pairingPath, deviceIP: deviceIP)
            result = code == ok ? .success(()) : .failure(.from(code: code))
        }
        return result
    }

    static func clear() -> Result<Void, LocationEngineError> {
        var result: Result<Void, LocationEngineError> = .failure(.notActive)
        queue.sync {
            let code = clearLocked()
            result = code == ok ? .success(()) : .failure(.from(code: code))
        }
        return result
    }

    private static func cleanup() {
        if let locationSimulation {
            location_simulation_free(locationSimulation)
            self.locationSimulation = nil
        }
        if let remoteServer {
            remote_server_free(remoteServer)
            self.remoteServer = nil
        }
        if let handshake {
            rsd_handshake_free(handshake)
            self.handshake = nil
        }
        if let adapter {
            adapter_free(adapter)
            self.adapter = nil
        }
    }

    private static func setLocked(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String) -> Int32 {
        lastStage = "reuse existing simulation"
        if let locationSimulation {
            if let err = location_simulation_set(locationSimulation, latitude, longitude) {
                // The existing handle may be invalid. Do not silently reconnect here:
                // a failed replacement can terminate an otherwise persistent GPS override.
                // User may explicitly Stop or restart the app to reset the handle.
                return failFFI(err, stage: "existing session update", code: locationSet)
            } else {
                lastStage = "existing session updated"
                lastFailure = "none"
                return ok
            }
        }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(TunnelConfig.targetPort).bigEndian
        let inetResult = deviceIP.withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
        guard inetResult == 1 else { return fail("invalid target IP", invalidIP) }

        var pairingHandle: OpaquePointer?
        if let pairingError = pairingPath.withCString({ rp_pairing_file_read($0, &pairingHandle) }) {
            return failFFI(pairingError, stage: "pairing file read", code: pairingRead,
                           pairingPath: pairingPath)
        }
        guard let pairingHandle else { return fail("pairing file handle", pairingRead) }
        defer { rp_pairing_file_free(pairingHandle) }

        lastStage = "opening RPPairing tunnel to \(deviceIP):\(TunnelConfig.targetPort)"
        let providerError = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                tunnel_create_rppairing(
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.stride),
                    "LocusLocation",
                    pairingHandle,
                    nil,
                    nil,
                    &adapter,
                    &handshake
                )
            }
        }
        if let providerError {
            let code = failFFI(providerError, stage: "tunnel_create_rppairing", code: tunnelCreate)
            cleanup()
            return code
        }

        lastStage = "RemoteXPC handshake"
        if let remoteServerError = remote_server_connect_rsd(adapter, handshake, &remoteServer) {
            let code = failFFI(remoteServerError, stage: "remote_server_connect_rsd", code: remoteServerCode)
            cleanup()
            return code
        }

        lastStage = "opening location simulation"
        if let simError = location_simulation_new(remoteServer, &locationSimulation) {
            let code = failFFI(simError, stage: "location_simulation_new", code: simulationCreate)
            cleanup()
            return code
        }
        // location_simulation_new consumes/owns remote server lifecycle alongside handle
        remoteServer = nil

        if let setError = location_simulation_set(locationSimulation, latitude, longitude) {
            let code = failFFI(setError, stage: "initial location_simulation_set", code: locationSet)
            cleanup()
            return code
        }
        lastStage = "location set succeeded"
        lastFailure = "none"
        return ok
    }

    private static func clearLocked() -> Int32 {
        guard let locationSimulation else { return fail("clear without retained session", locationClear) }
        // v0.11: A failed clear must NOT discard our only usable RSD handle.
        // Under cellular, reopening a new developer connection can fail, while
        // the already-established session may still accept location updates.
        if let err = location_simulation_clear(locationSimulation) {
            return failFFI(err, stage: "location_simulation_clear failed (session handle retained)",
                           code: locationClear)
        }
        cleanup()
        lastStage = "location simulation cleared"
        lastFailure = "none"
        return ok
    }
}
