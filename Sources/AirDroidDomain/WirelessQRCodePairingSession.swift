public struct WirelessQRCodePairingSession: Equatable, Identifiable, Sendable {
    public let serviceName: String
    public let password: String

    public var id: String { serviceName }
    public var payload: String {
        "WIFI:T:ADB;S:\(serviceName);P:\(password);;"
    }

    public init(serviceName: String, password: String) {
        self.serviceName = serviceName
        self.password = password
    }
}
