import Foundation

enum TunnelConfig {
    /// LocalDevVPN / SideStore-style loopback tunnel endpoint.
    static let defaultIP = "10.7.0.1"
    static let defaultsKey = "locus.targetDeviceIP"

    static var targetIP: String {
        let stored = UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stored, !stored.isEmpty else { return defaultIP }
        return stored
    }

    static var targetPort: UInt16 {
        let value = UserDefaults.standard.integer(forKey: "roam.developerPort")
        return (1...65535).contains(value) ? UInt16(value) : 49152
    }

    static func setTargetPort(_ value: String) {
        guard let parsed = UInt16(value), parsed > 0 else { return }
        UserDefaults.standard.set(Int(parsed), forKey: "roam.developerPort")
    }

    static func setTargetIP(_ value: String) {
        UserDefaults.standard.set(value, forKey: defaultsKey)
    }
}
