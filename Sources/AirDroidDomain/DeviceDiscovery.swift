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
    public let host: String
    public let port: Int

    public var id: String { "\(serviceName)-\(host)-\(port)" }

    public init(serviceName: String, host: String, port: Int) {
        self.serviceName = serviceName
        self.host = host
        self.port = port
    }
}

public struct WirelessConnectionCandidate: Hashable, Identifiable, Sendable {
    public let serviceName: String
    public let host: String
    public let port: Int

    public var id: String { "\(serviceName)-\(host)-\(port)" }

    public init(serviceName: String, host: String, port: Int) {
        self.serviceName = serviceName
        self.host = host
        self.port = port
    }
}

public struct DeviceDiscoverySnapshot: Equatable, Sendable {
    public let devices: [DiscoveredDevice]
    public let pairingCandidates: [PairingCandidate]
    public let wirelessConnectionCandidates: [WirelessConnectionCandidate]

    public init(
        devices: [DiscoveredDevice],
        pairingCandidates: [PairingCandidate],
        wirelessConnectionCandidates: [WirelessConnectionCandidate]
    ) {
        self.devices = devices
        self.pairingCandidates = pairingCandidates
        self.wirelessConnectionCandidates = wirelessConnectionCandidates
    }

    public func wirelessConnectionCandidate(
        matching pairingCandidate: PairingCandidate
    ) -> WirelessConnectionCandidate? {
        wirelessConnectionCandidates.first(where: { candidate in
            candidate.host == pairingCandidate.host
        })
    }
}

public protocol DeviceDiscovery {
    func discover() throws -> DeviceDiscoverySnapshot
}
