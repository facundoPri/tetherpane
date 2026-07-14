public enum ConnectionManagement: Equatable, Sendable {
    case unplugUSB
    case disconnectOnThisMac
    case turnOffWirelessUntilRestart
    case disconnectUnverifiedEndpoint
    case none
}

public struct ConnectionPanelPresentation: Equatable, Sendable {
    public let title: String
    public let status: String
    public let security: String
    public let lifecycle: String
    public let management: ConnectionManagement

    public init(
        title: String,
        status: String,
        security: String,
        lifecycle: String,
        management: ConnectionManagement
    ) {
        self.title = title
        self.status = status
        self.security = security
        self.lifecycle = lifecycle
        self.management = management
    }

    public init(route: ConnectionRoute) {
        switch route {
        case .directUSB:
            self.init(
                title: "USB-C",
                status: "Connected automatically",
                security: "Direct cable connection",
                lifecycle: "Unplug the cable whenever you want to disconnect this route.",
                management: .unplugUSB
            )
        case .secureWirelessDebugging:
            self.init(
                title: "Wireless Debugging",
                status: "Connected securely",
                security: "Encrypted by Android",
                lifecycle: "Disconnecting here closes only this Mac's current connection. Android may continue to remember this Mac.",
                management: .disconnectOnThisMac
            )
        case .legacyWirelessUntilRestart:
            self.init(
                title: "Wi-Fi until restart",
                status: "Connected",
                security: "Unencrypted on your local network",
                lifecycle: "Turn it off here or restart the phone to close the wireless ADB listener.",
                management: .turnOffWirelessUntilRestart
            )
        case .unclassifiedWireless:
            self.init(
                title: "Wi-Fi connection",
                status: "Route unverified",
                security: "Security not verified",
                lifecycle: "TetherPane can close this exact local endpoint, but cannot claim its Android authorization lifetime.",
                management: .disconnectUnverifiedEndpoint
            )
        case .emulator:
            self.init(
                title: "Android emulator",
                status: "Connected locally",
                security: "Local development endpoint",
                lifecycle: "Manage this endpoint from the emulator or Android development tools.",
                management: .none
            )
        }
    }
}
