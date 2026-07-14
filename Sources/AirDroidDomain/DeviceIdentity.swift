import Foundation

public struct DeviceIdentity: Hashable, Identifiable, Sendable {
    public let serial: String
    public let displayName: String

    public var id: String { serial }

    public init(serial: String, displayName: String) {
        self.serial = serial
        self.displayName = displayName
    }
}
