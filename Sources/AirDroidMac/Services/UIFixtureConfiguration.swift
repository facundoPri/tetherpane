import AirDroidDomain
import Foundation

enum UIFixture: String {
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

    static var active: UIFixture? {
        let environment = ProcessInfo.processInfo.environment
        return (environment["TETHERPANE_UI_FIXTURE"] ?? environment["AIRDROID_UI_FIXTURE"])
            .flatMap(UIFixture.init(rawValue:))
    }
}

struct UIFixtureStoreSeed {
    var savedRecords: [SavedDeviceRecord] = []
    var selectedSavedRecordID: DeviceRecordID?
    var legacyScenario: UIFixtureLegacyScenario?
}

struct UIFixtureScenario {
    let discoverySnapshot: DeviceDiscoverySnapshot
    var storeSeed = UIFixtureStoreSeed()
}

enum UIFixtureLegacyScenario {
    case enabling(sourceUSB: DiscoveredDevice)
    case safeToUnplug(sourceUSB: DiscoveredDevice, wireless: DiscoveredDevice)
}

extension UIFixture {
    var scenario: UIFixtureScenario {
        let identity = DeviceIdentity(
            serial: "ui-fixture-exact",
            displayName: "Fixture Android Phone"
        )
        let sourceUSB = DiscoveredDevice(
            identity: identity,
            state: .authorized,
            transport: .usb
        )

        switch self {
        case .usbUnauthorized:
            return UIFixtureScenario(
                discoverySnapshot: DeviceDiscoverySnapshot(
                    devices: [
                        DiscoveredDevice(
                            identity: identity,
                            state: .unauthorized,
                            transport: .usb
                        ),
                    ],
                    pairingCandidates: [],
                    wirelessConnectionCandidates: []
                )
            )
        case .usbReady:
            return UIFixtureScenario(
                discoverySnapshot: DeviceDiscoverySnapshot(
                    devices: [sourceUSB],
                    pairingCandidates: [],
                    wirelessConnectionCandidates: []
                )
            )
        case .multiUSBDistinct:
            return UIFixtureScenario(
                discoverySnapshot: DeviceDiscoverySnapshot(
                    devices: [
                        sourceUSB,
                        DiscoveredDevice(
                            identity: DeviceIdentity(
                                serial: "ui-fixture-second-exact",
                                displayName: "Fixture Tablet"
                            ),
                            state: .authorized,
                            transport: .usb
                        ),
                    ],
                    pairingCandidates: [],
                    wirelessConnectionCandidates: []
                )
            )
        case .multiUSBAmbiguous:
            return UIFixtureScenario(
                discoverySnapshot: DeviceDiscoverySnapshot(
                    devices: [
                        sourceUSB,
                        DiscoveredDevice(
                            identity: DeviceIdentity(
                                serial: "ui-fixture-same-name-exact",
                                displayName: identity.displayName
                            ),
                            state: .authorized,
                            transport: .usb
                        ),
                    ],
                    pairingCandidates: [],
                    wirelessConnectionCandidates: []
                )
            )
        case .usbWithWirelessWarning:
            return UIFixtureScenario(
                discoverySnapshot: DeviceDiscoverySnapshot(
                    devices: [sourceUSB],
                    pairingCandidates: [],
                    wirelessConnectionCandidates: [],
                    wirelessDiscoveryWarning: "Fixture mDNS service is unavailable."
                )
            )
        case .secureNearby:
            return UIFixtureScenario(
                discoverySnapshot: DeviceDiscoverySnapshot(
                    devices: [],
                    pairingCandidates: [],
                    wirelessConnectionCandidates: [secureConnectionCandidate]
                )
            )
        case .securePairing:
            return UIFixtureScenario(
                discoverySnapshot: DeviceDiscoverySnapshot(
                    devices: [],
                    pairingCandidates: [
                        PairingCandidate(
                            serviceName: "ui-fixture-pairing",
                            host: "192.0.2.80",
                            port: 37222
                        ),
                    ],
                    wirelessConnectionCandidates: [secureConnectionCandidate]
                )
            )
        case .legacyEnabling:
            return UIFixtureScenario(
                discoverySnapshot: DeviceDiscoverySnapshot(
                    devices: [sourceUSB],
                    pairingCandidates: [],
                    wirelessConnectionCandidates: []
                ),
                storeSeed: UIFixtureStoreSeed(
                    legacyScenario: .enabling(sourceUSB: sourceUSB)
                )
            )
        case .legacySafeToUnplug:
            let wireless = DiscoveredDevice(
                identity: DeviceIdentity(
                    serial: "192.0.2.44:5555",
                    displayName: identity.displayName
                ),
                state: .authorized,
                transport: .wireless
            )
            return UIFixtureScenario(
                discoverySnapshot: DeviceDiscoverySnapshot(
                    devices: [sourceUSB, wireless],
                    pairingCandidates: [],
                    wirelessConnectionCandidates: []
                ),
                storeSeed: UIFixtureStoreSeed(
                    legacyScenario: .safeToUnplug(
                        sourceUSB: sourceUSB,
                        wireless: wireless
                    )
                )
            )
        case .deviceManagement:
            return UIFixtureScenario(
                discoverySnapshot: DeviceDiscoverySnapshot(
                    devices: [
                        sourceUSB,
                        DiscoveredDevice(
                            identity: DeviceIdentity(
                                serial: "192.0.2.80:37123",
                                displayName: "Living Room Phone"
                            ),
                            state: .authorized,
                            transport: .wireless
                        ),
                    ],
                    pairingCandidates: [],
                    wirelessConnectionCandidates: [secureConnectionCandidate]
                ),
                storeSeed: UIFixtureStoreSeed(savedRecords: [
                    SavedDeviceRecord(
                        id: .usb(serial: "ui-fixture-offline"),
                        displayName: "Travel Phone",
                        lastRoute: .usbC
                    ),
                ])
            )
        case .secureDisconnected:
            return UIFixtureScenario(
                discoverySnapshot: DeviceDiscoverySnapshot(
                    devices: [],
                    pairingCandidates: [],
                    wirelessConnectionCandidates: [
                        WirelessConnectionCandidate(
                            serviceName: "ui-fixture-disconnected",
                            host: "192.0.2.81",
                            port: 38123
                        ),
                    ]
                ),
                storeSeed: UIFixtureStoreSeed(
                    savedRecords: [
                        SavedDeviceRecord(
                            id: .secureService(name: "ui-fixture-disconnected"),
                            displayName: "Living Room Phone",
                            lastRoute: .secureWiFi,
                            isLocallyDisconnected: true
                        ),
                    ],
                    selectedSavedRecordID: .secureService(
                        name: "ui-fixture-disconnected"
                    )
                )
            )
        case .unclassifiedWireless:
            return UIFixtureScenario(
                discoverySnapshot: DeviceDiscoverySnapshot(
                    devices: [
                        DiscoveredDevice(
                            identity: DeviceIdentity(
                                serial: "192.0.2.91:40991",
                                displayName: "Unverified Android Endpoint"
                            ),
                            state: .authorized,
                            transport: .wireless
                        ),
                    ],
                    pairingCandidates: [],
                    wirelessConnectionCandidates: []
                )
            )
        }
    }

    private var secureConnectionCandidate: WirelessConnectionCandidate {
        WirelessConnectionCandidate(
            serviceName: "ui-fixture-secure",
            host: "192.0.2.80",
            port: 37123
        )
    }
}

struct UIFixtureActionError: LocalizedError {
    var errorDescription: String? {
        "This inert UI fixture never runs ADB or scrcpy commands."
    }
}
