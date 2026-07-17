import Foundation

@frozen
public enum UIFixture: String, CaseIterable, Sendable {
    case usbUnauthorized = "usb-unauthorized"
    case usbReady = "usb-ready"
    case multiUSBDistinct = "multi-usb-distinct"
    case multiUSBAmbiguous = "multi-usb-ambiguous"
    case usbWithWirelessWarning = "usb-with-wireless-warning"
    case secureNearby = "secure-nearby"
    case securePairing = "secure-pairing"
    case legacyEnabling = "legacy-enabling"
    case legacySafeToUnplug = "legacy-safe-to-unplug"
    case deviceManagement = "device-management"
    case secureDisconnected = "secure-disconnected"
    case unclassifiedWireless = "unclassified-wireless"

    public static var active: UIFixture? {
        active(in: ProcessInfo.processInfo.environment)
    }

    public static func active(in environment: [String: String]) -> UIFixture? {
        (environment["TETHERPANE_UI_FIXTURE"] ?? environment["AIRDROID_UI_FIXTURE"])
            .flatMap(UIFixture.init(rawValue:))
    }
}

public struct UIFixturePresentationProfile: Equatable, Sendable {
    public enum Appearance: String, Equatable, Sendable {
        case system
        case light
        case dark
    }

    public static let system = UIFixturePresentationProfile(
        appearance: .system,
        reduceMotion: nil,
        reduceTransparency: nil
    )

    public let appearance: Appearance
    public let reduceMotion: Bool?
    public let reduceTransparency: Bool?

    public init(environment: [String: String]) {
        guard UIFixture.active(in: environment) != nil else {
            self = .system
            return
        }

        appearance = environment["TETHERPANE_UI_APPEARANCE"]
            .flatMap(Appearance.init(rawValue:))
            ?? .system
        reduceMotion = Self.parseBoolean(
            environment["TETHERPANE_UI_REDUCE_MOTION"]
        )
        reduceTransparency = Self.parseBoolean(
            environment["TETHERPANE_UI_REDUCE_TRANSPARENCY"]
        )
    }

    private init(
        appearance: Appearance,
        reduceMotion: Bool?,
        reduceTransparency: Bool?
    ) {
        self.appearance = appearance
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
    }

    private static func parseBoolean(_ rawValue: String?) -> Bool? {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            true
        case "0", "false", "no", "off":
            false
        default:
            nil
        }
    }
}
