public struct WirelessConnection: Equatable, Sendable {
    public let deviceSerial: String

    public init(deviceSerial: String) {
        self.deviceSerial = deviceSerial
    }
}

public protocol WirelessConnectionClient: Sendable {
    /// Connects one mDNS-discovered Wireless Debugging endpoint and returns its exact ADB serial.
    func connect(candidate: WirelessConnectionCandidate) throws -> WirelessConnection

    /// Restarts ADB on one already-authorized USB device in classic TCP/IP mode, connects its
    /// Wi-Fi endpoint, and returns the exact ADB serial that scrcpy must target.
    func connectOverTCPIP(device: DeviceIdentity) throws -> WirelessConnection

    /// Opens Android's public Developer Options settings action on one exact authorized device.
    /// Android remains responsible for every visible setting change and authorization decision.
    func openDeveloperOptions(device: DeviceIdentity) throws

    /// Closes one proven classic TCP/IP listener, or conservatively restarts adbd through its
    /// exact USB source after an interrupted setup. Only network routes are disconnected.
    func disableTCPIP(endpoint: ADBEndpoint) throws

    /// Disconnects one exact secure or unclassified wireless ADB endpoint on this Mac. This does
    /// not revoke Android's Wireless Debugging authorization or change a setting on the phone.
    func disconnect(endpoint: ADBEndpoint) throws
}
