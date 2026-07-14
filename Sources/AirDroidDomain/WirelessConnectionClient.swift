public struct WirelessConnection: Equatable, Sendable {
    public let deviceSerial: String

    public init(deviceSerial: String) {
        self.deviceSerial = deviceSerial
    }
}

public protocol WirelessConnectionClient {
    /// Connects one mDNS-discovered Wireless Debugging endpoint and returns its exact ADB serial.
    func connect(candidate: WirelessConnectionCandidate) throws -> WirelessConnection

    /// Restarts ADB on one already-authorized USB device in classic TCP/IP mode, connects its
    /// Wi-Fi endpoint, and returns the exact ADB serial that scrcpy must target.
    func connectOverTCPIP(device: DeviceIdentity) throws -> WirelessConnection

    /// Opens Android's public Developer Options settings action on one exact authorized device.
    /// Android remains responsible for every visible setting change and authorization decision.
    func openDeveloperOptions(device: DeviceIdentity) throws

    /// Closes one device's classic TCP/IP listener by restarting adbd in USB mode.
    func disableTCPIP(device: DeviceIdentity) throws
}
