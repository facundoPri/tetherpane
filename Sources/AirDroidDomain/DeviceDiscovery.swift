public enum DeviceConnectionState: Hashable, Sendable {
    case authorized
    case offline
    case unauthorized
    case unknown(String)
}

public enum DeviceTransport: Hashable, Sendable {
    case usb
    case wireless
    case emulator
    case unknown
}

public struct DiscoveredDevice: Hashable, Identifiable, Sendable {
    public let identity: DeviceIdentity
    public let state: DeviceConnectionState
    public let transport: DeviceTransport

    public var id: String { identity.id }

    public init(
        identity: DeviceIdentity,
        state: DeviceConnectionState,
        transport: DeviceTransport = .unknown
    ) {
        self.identity = identity
        self.state = state
        self.transport = transport
    }
}

public struct PairingCandidate: Hashable, Identifiable, Sendable {
    public let serviceName: String
    public let endpoint: ADBNetworkEndpoint

    public var id: String { "\(serviceName)-\(endpoint.adbAddress)" }
    public var host: String { endpoint.host }
    public var port: Int { endpoint.port }

    public init(serviceName: String, host: String, port: Int) {
        self.serviceName = serviceName
        endpoint = ADBNetworkEndpoint(host: host, port: port)
    }
}

public struct WirelessConnectionCandidate: Hashable, Identifiable, Sendable {
    public let serviceName: String
    public let endpoint: ADBNetworkEndpoint

    public var id: String { "\(serviceName)-\(endpoint.adbAddress)" }
    public var host: String { endpoint.host }
    public var port: Int { endpoint.port }

    public init(serviceName: String, host: String, port: Int) {
        self.serviceName = serviceName
        endpoint = ADBNetworkEndpoint(host: host, port: port)
    }
}

public struct ADBNetworkEndpoint: Hashable, Sendable, CustomStringConvertible {
    public let host: String
    public let port: Int

    public var adbAddress: String {
        let formattedHost = host.contains(":") ? "[\(host)]" : host
        return "\(formattedHost):\(port)"
    }

    public var description: String { adbAddress }

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
}

public struct DeviceDiscoverySnapshot: Equatable, Sendable {
    public let devices: [DiscoveredDevice]
    public let pairingCandidates: [PairingCandidate]
    public let wirelessConnectionCandidates: [WirelessConnectionCandidate]
    public let wirelessDiscoveryWarning: String?

    public init(
        devices: [DiscoveredDevice],
        pairingCandidates: [PairingCandidate],
        wirelessConnectionCandidates: [WirelessConnectionCandidate],
        wirelessDiscoveryWarning: String? = nil
    ) {
        self.devices = devices
        self.pairingCandidates = pairingCandidates
        self.wirelessConnectionCandidates = wirelessConnectionCandidates
        self.wirelessDiscoveryWarning = wirelessDiscoveryWarning
    }

    public func wirelessConnectionCandidate(
        matching pairingCandidate: PairingCandidate
    ) -> WirelessConnectionCandidate? {
        let matches = wirelessConnectionCandidates.filter { candidate in
            candidate.host == pairingCandidate.host
        }
        return matches.count == 1 ? matches[0] : nil
    }
}

public protocol DeviceDiscovery: Sendable {
    func discover() throws -> DeviceDiscoverySnapshot
}
