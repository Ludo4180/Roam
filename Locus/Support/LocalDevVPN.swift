import Darwin
import Foundation
import UIKit

/// Best-effort observation of a VPN-like network interface. iOS does not let
/// Roam authenticate or manage another app's NetworkExtension configuration.
/// In particular, seeing this interface does NOT prove LocalDevVPN is connected
/// or that the paired developer service is reachable.
enum LocalDevVPN {
    static let appStoreURL = URL(string: "https://apps.apple.com/us/app/localdevvpn/id6755608044")!
    static let detectURL = URL(string: "localdevvpn://")!

    /// Starts the tunnel, then returns to Roam via the registered `roamdiagnostics://` callback.
    static let enableURL = URL(string: "localdevvpn://enable?scheme=roamdiagnostics")!

    struct TunnelCandidate {
        let name: String
        let address: String
    }

    static var isInstalled: Bool {
        UIApplication.shared.canOpenURL(detectURL)
    }

    /// The observed LocalDevVPN client address is 10.7.1.1. It is NOT the
    /// developer service endpoint (usually 10.7.0.1). Never substitute one
    /// for the other in the pairing or location engine.
    static var tunnelCandidate: TunnelCandidate? {
        let target = TunnelConfig.targetIP
        let octets = target.split(separator: ".")
        let optionalTargetPrefix = octets.count == 4
            ? octets.dropLast().joined(separator: ".") + "."
            : nil

        return ipv4UTunAddresses().first { candidate in
            candidate.address == "10.7.1.1" ||
                (optionalTargetPrefix.map { candidate.address.hasPrefix($0) } ?? false)
        }
    }

    /// Compatibility for existing screens: this is only a candidate, NOT
    /// an authenticated "LocalDevVPN connected" indication.
    static var isConnected: Bool { tunnelCandidate != nil }

    static var candidateDescription: String {
        guard let candidate = tunnelCandidate else {
            return "No matching utun interface found — check Settings > VPN"
        }
        return "Candidate \(candidate.name): \(candidate.address) (unverified)"
    }

    static func openInstalled() {
        UIApplication.shared.open(enableURL)
    }

    static func openAppStore() {
        UIApplication.shared.open(appStoreURL)
    }

    static func openOrInstall() {
        if isInstalled {
            openInstalled()
        } else {
            openAppStore()
        }
    }

    private static func ipv4UTunAddresses() -> [TunnelCandidate] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var results: [TunnelCandidate] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let item = current.pointee
            let name = String(cString: item.ifa_name)
            if name.hasPrefix("utun"),
               (item.ifa_flags & UInt32(IFF_UP)) != 0,
               let address = item.ifa_addr,
               address.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    address,
                    socklen_t(MemoryLayout<sockaddr_in>.size),
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    results.append(TunnelCandidate(name: name, address: String(cString: host)))
                }
            }
            ptr = item.ifa_next
        }
        // Prefer the exact observed client IP over any endpoint-prefix match.
        return results.sorted {
            ($0.address == "10.7.1.1" ? 0 : 1, $0.name) <
                ($1.address == "10.7.1.1" ? 0 : 1, $1.name)
        }
    }
}
