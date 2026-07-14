public struct WirelessConnection: Equatable, Sendable {
    public let deviceSerial: String

    public init(deviceSerial: String) {
        self.deviceSerial = deviceSerial
    }
}

public protocol WirelessConnectionClient {
    /// Connects one mDNS-discovered Wireless Debugging endpoint and returns its exact ADB serial.
    func connect(candidate: WirelessConnectionCandidate) throws -> WirelessConnection
}
