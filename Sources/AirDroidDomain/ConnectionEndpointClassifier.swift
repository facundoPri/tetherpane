public struct ConnectionEndpointClassifier: Sendable {
    public private(set) var verifiedLegacySources: [String: String]
    public private(set) var verifiedSecureServices: [String: String]

    public init(
        verifiedLegacySources: [String: String] = [:],
        verifiedSecureServices: [String: String] = [:]
    ) {
        self.verifiedLegacySources = verifiedLegacySources
        self.verifiedSecureServices = verifiedSecureServices
    }

    public mutating func recordLegacyTransition(
        sourceUSBSerial: String,
        wirelessSerial: String
    ) {
        verifiedLegacySources[wirelessSerial] = sourceUSBSerial
    }

    public mutating func removeLegacyTransition(for wirelessSerial: String) {
        verifiedLegacySources[wirelessSerial] = nil
    }

    public mutating func recordSecureService(
        _ serviceName: String,
        for wirelessSerial: String
    ) {
        verifiedSecureServices[wirelessSerial] = serviceName
    }

    public func endpoint(
        for device: DiscoveredDevice,
        wirelessCandidates: [WirelessConnectionCandidate]
    ) -> ADBEndpoint {
        switch device.transport {
        case .usb:
            return ADBEndpoint(
                identity: device.identity,
                authorization: device.state,
                route: .directUSB,
                provenance: .adbUSBObservation
            )
        case .emulator:
            return ADBEndpoint(
                identity: device.identity,
                authorization: device.state,
                route: .emulator,
                provenance: .emulatorObservation
            )
        case .wireless:
            return wirelessEndpoint(
                for: device,
                wirelessCandidates: wirelessCandidates
            )
        case .unknown:
            return ADBEndpoint(
                identity: device.identity,
                authorization: device.state,
                route: .unclassifiedWireless,
                provenance: .unverified
            )
        }
    }

    private func wirelessEndpoint(
        for device: DiscoveredDevice,
        wirelessCandidates: [WirelessConnectionCandidate]
    ) -> ADBEndpoint {
        if let serviceName = verifiedSecureServices[device.identity.serial] {
            return ADBEndpoint(
                identity: device.identity,
                authorization: device.state,
                route: .secureWirelessDebugging,
                provenance: .secureServiceObservation(serviceName: serviceName)
            )
        }
        if let candidate = wirelessCandidates.first(where: {
            $0.endpoint.adbAddress == device.identity.serial
                || "\($0.serviceName)._adb-tls-connect._tcp" == device.identity.serial
        }) {
            return ADBEndpoint(
                identity: device.identity,
                authorization: device.state,
                route: .secureWirelessDebugging,
                provenance: .secureServiceObservation(
                    serviceName: candidate.serviceName
                )
            )
        }
        if let sourceUSBSerial = verifiedLegacySources[device.identity.serial] {
            return ADBEndpoint(
                identity: device.identity,
                authorization: device.state,
                route: .legacyWirelessUntilRestart,
                provenance: .appInitiatedLegacyTransition(
                    sourceUSBSerial: sourceUSBSerial,
                    wirelessSerial: device.identity.serial
                )
            )
        }
        return ADBEndpoint(
            identity: device.identity,
            authorization: device.state,
            route: .unclassifiedWireless,
            provenance: .unverified
        )
    }
}
