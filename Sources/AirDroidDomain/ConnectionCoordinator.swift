public enum ConnectionWorkspacePresentation: Equatable, Sendable {
    case disconnected
    case usbDisambiguationRequired(candidateCount: Int)
    case usbAuthorizationRequired(DeviceIdentity)
    case ready(ADBEndpoint)
    case legacyEnabling(ADBEndpoint)
    case legacySafeToUnplug(ADBEndpoint)
    case secureWirelessNearby(candidateCount: Int)
    case securePairing(candidateCount: Int)
    case mirroring(ADBEndpoint)

    public var endpoint: ADBEndpoint? {
        switch self {
        case let .ready(endpoint),
             let .legacyEnabling(endpoint),
             let .legacySafeToUnplug(endpoint),
             let .mirroring(endpoint):
            endpoint
        case .disconnected,
             .usbDisambiguationRequired,
             .usbAuthorizationRequired,
             .secureWirelessNearby,
             .securePairing:
            nil
        }
    }

    public var navigationTitle: String {
        if let endpoint {
            return endpoint.identity.displayName
        }
        switch self {
        case .disconnected:
            return "Connect your Android phone"
        case .usbDisambiguationRequired:
            return "Connect one phone"
        case .usbAuthorizationRequired:
            return "Authorize your phone"
        case .secureWirelessNearby, .securePairing:
            return "Connect over Wi-Fi"
        case .ready, .legacyEnabling, .legacySafeToUnplug, .mirroring:
            preconditionFailure("Endpoint-backed workspaces return before this switch")
        }
    }
}

public struct ControlCenterPresentation: Equatable, Sendable {
    public let workspace: ConnectionWorkspacePresentation
    public let notice: ConnectionNotice?

    public init(
        workspace: ConnectionWorkspacePresentation,
        notice: ConnectionNotice? = nil
    ) {
        self.workspace = workspace
        self.notice = notice
    }
}

public struct ConnectionCoordinator: Sendable {
    private var endpoints: [ADBEndpoint] = []
    private var activeLegacySourceSerial: String?
    private var verifiedLegacyEndpoint: ADBEndpoint?
    private var nearbySecureEndpointCount = 0
    private var pairingAvailable = false
    private var activeMirroringEndpoint: ADBEndpoint?
    private var notices: [ConnectionNoticeScope: ConnectionNotice] = [:]
    private var operationGenerations: [ConnectionNoticeScope: UInt64] = [:]
    private var selectedEndpointSerial: String?

    public init() {}

    public mutating func beginOperation(
        scope: ConnectionNoticeScope,
        message: String,
        showsProgress: Bool = true
    ) -> ConnectionOperationToken {
        if scope == .wirelessSetup {
            activeLegacySourceSerial = nil
        }
        let generation = operationGenerations[scope, default: 0] + 1
        operationGenerations[scope] = generation
        if showsProgress {
            notices[scope] = ConnectionNotice(
                scope: scope,
                kind: .progress,
                message: message
            )
        }
        return ConnectionOperationToken(scope: scope, generation: generation)
    }

    public var presentation: ControlCenterPresentation {
        if let activeMirroringEndpoint {
            return makePresentation(workspace: .mirroring(activeMirroringEndpoint))
        }
        if let selectedEndpointSerial,
           let verifiedLegacyEndpoint,
           verifiedLegacyEndpoint.identity.serial == selectedEndpointSerial {
            return makePresentation(
                workspace: .legacySafeToUnplug(verifiedLegacyEndpoint)
            )
        }
        if let selectedEndpointSerial,
           let endpoint = endpoints.first(where: {
               $0.identity.serial == selectedEndpointSerial
           }) {
            if activeLegacySourceSerial == selectedEndpointSerial,
               endpoint.route == .directUSB,
               endpoint.authorization == .authorized {
                return makePresentation(workspace: .legacyEnabling(endpoint))
            }
            if endpoint.authorization == .authorized,
               isVerifiedLegacy(endpoint) {
                return makePresentation(workspace: .legacySafeToUnplug(endpoint))
            }
            if endpoint.route == .directUSB, endpoint.authorization == .unauthorized {
                return makePresentation(
                    workspace: .usbAuthorizationRequired(endpoint.identity)
                )
            }
            if endpoint.authorization == .authorized,
               endpoint.route == .directUSB
                   || endpoint.route == .unclassifiedWireless
                   || endpoint.route == .emulator
                   || isVerifiedSecure(endpoint) {
                return makePresentation(workspace: .ready(endpoint))
            }
        }
        if selectedEndpointSerial == nil {
            if let verifiedLegacyEndpoint {
                return makePresentation(
                    workspace: .legacySafeToUnplug(verifiedLegacyEndpoint)
                )
            }
            if let endpoint = endpoints.first(where: { endpoint in
                endpoint.authorization == .authorized && isVerifiedLegacy(endpoint)
            }) {
                return makePresentation(workspace: .legacySafeToUnplug(endpoint))
            }
            if let activeLegacySourceSerial,
               let endpoint = endpoints.first(where: {
                   $0.identity.serial == activeLegacySourceSerial
                       && $0.route == .directUSB
                       && $0.authorization == .authorized
               }) {
                return makePresentation(workspace: .legacyEnabling(endpoint))
            }
            let usbEndpoints = endpoints.filter { $0.route == .directUSB }
            let displayNames = Set(usbEndpoints.map(\.identity.displayName))
            if usbEndpoints.count > 1, displayNames.count != usbEndpoints.count {
                return makePresentation(
                    workspace: .usbDisambiguationRequired(
                        candidateCount: usbEndpoints.count
                    )
                )
            }
        }
        if let endpoint = endpoints.first(where: {
            $0.route == .directUSB && $0.authorization == .authorized
        }) {
            return makePresentation(workspace: .ready(endpoint))
        }
        if let endpoint = endpoints.first(where: { endpoint in
            endpoint.authorization == .authorized && isVerifiedSecure(endpoint)
        }) {
            return makePresentation(workspace: .ready(endpoint))
        }
        if let endpoint = endpoints.first(where: {
            $0.authorization == .authorized && $0.route == .unclassifiedWireless
        }) {
            return makePresentation(workspace: .ready(endpoint))
        }
        if let endpoint = endpoints.first(where: {
            $0.route == .directUSB && $0.authorization == .unauthorized
        }) {
            return makePresentation(
                workspace: .usbAuthorizationRequired(endpoint.identity)
            )
        }
        if pairingAvailable {
            return makePresentation(
                workspace: .securePairing(candidateCount: nearbySecureEndpointCount)
            )
        }
        if nearbySecureEndpointCount > 0 {
            return makePresentation(
                workspace: .secureWirelessNearby(candidateCount: nearbySecureEndpointCount)
            )
        }
        return makePresentation(workspace: .disconnected)
    }

    @discardableResult
    public mutating func send(_ event: ConnectionCoordinatorEvent) -> Bool {
        switch event {
        case let .discoveryUpdated(
            endpoints,
            nearbySecureEndpointCount,
            pairingAvailable
        ):
            applyDiscovery(
                endpoints: endpoints,
                nearbySecureEndpointCount: nearbySecureEndpointCount,
                pairingAvailable: pairingAvailable
            )
        case let .discoveryCompleted(
            token,
            endpoints,
            nearbySecureEndpointCount,
            pairingAvailable
        ):
            guard isCurrent(token) else { return false }
            applyDiscovery(
                endpoints: endpoints,
                nearbySecureEndpointCount: nearbySecureEndpointCount,
                pairingAvailable: pairingAvailable
            )
        case let .discoveryFailed(token, message):
            guard isCurrent(token) else { return false }
            applyDiscovery(
                endpoints: [],
                nearbySecureEndpointCount: 0,
                pairingAvailable: false
            )
            notices[.discovery] = ConnectionNotice(
                scope: .discovery,
                kind: .failure,
                message: message,
                recovery: .refresh
            )
        case let .legacySetupStarted(sourceUSBSerial):
            guard endpoints.contains(where: {
                $0.identity.serial == sourceUSBSerial
                    && $0.route == .directUSB
                    && $0.authorization == .authorized
            }) else {
                return false
            }
            activeLegacySourceSerial = sourceUSBSerial
            verifiedLegacyEndpoint = nil
        case let .legacySetupFailed(sourceUSBSerial):
            guard activeLegacySourceSerial == sourceUSBSerial else { return false }
            activeLegacySourceSerial = nil
        case let .legacySetupCompleted(sourceUSBSerial, wirelessIdentity):
            guard activeLegacySourceSerial == sourceUSBSerial else { return false }
            verifiedLegacyEndpoint = ADBEndpoint(
                identity: wirelessIdentity,
                authorization: .authorized,
                route: .legacyWirelessUntilRestart,
                provenance: .appInitiatedLegacyTransition(
                    sourceUSBSerial: sourceUSBSerial,
                    wirelessSerial: wirelessIdentity.serial
                )
            )
            selectedEndpointSerial = wirelessIdentity.serial
            activeLegacySourceSerial = nil
        case let .legacyTurnedOff(wirelessSerial):
            let hasRestoredLegacyEndpoint = endpoints.contains(where: {
                $0.identity.serial == wirelessSerial && isVerifiedLegacy($0)
            })
            guard verifiedLegacyEndpoint?.identity.serial == wirelessSerial
                    || hasRestoredLegacyEndpoint
            else {
                return false
            }
            verifiedLegacyEndpoint = nil
            endpoints.removeAll(where: { $0.identity.serial == wirelessSerial })
            if selectedEndpointSerial == wirelessSerial {
                selectedEndpointSerial = nil
            }
        case let .mirroringStarted(endpointSerial):
            let endpoint = endpoints.first(where: {
                $0.identity.serial == endpointSerial && $0.authorization == .authorized
            }) ?? (verifiedLegacyEndpoint?.identity.serial == endpointSerial
                ? verifiedLegacyEndpoint
                : nil)
            guard let endpoint else { return false }
            activeMirroringEndpoint = endpoint
            notices[.mirroring] = nil
        case .mirroringStopped:
            activeMirroringEndpoint = nil
            notices[.mirroring] = nil
        case let .operationFailed(scope, message, recovery):
            notices[scope] = ConnectionNotice(
                scope: scope,
                kind: .failure,
                message: message,
                recovery: recovery
            )
        case let .noticeUpdated(notice):
            notices[notice.scope] = notice
        case let .noticeCleared(scope):
            notices[scope] = nil
        case let .endpointSelected(serial):
            guard endpoints.contains(where: { $0.identity.serial == serial }) else { return false }
            selectedEndpointSerial = serial
        }
        return true
    }

    private func makePresentation(
        workspace: ConnectionWorkspacePresentation
    ) -> ControlCenterPresentation {
        let notice = [
            ConnectionNoticeScope.mirroring,
            .wirelessSetup,
            .wirelessDiscovery,
            .discovery,
        ].compactMap { notices[$0] }.first
        return ControlCenterPresentation(workspace: workspace, notice: notice)
    }

    private mutating func applyDiscovery(
        endpoints: [ADBEndpoint],
        nearbySecureEndpointCount: Int,
        pairingAvailable: Bool
    ) {
        self.endpoints = endpoints
        self.nearbySecureEndpointCount = nearbySecureEndpointCount
        self.pairingAvailable = pairingAvailable
        if let verifiedLegacyEndpoint,
           !endpoints.contains(where: {
               $0.identity.serial == verifiedLegacyEndpoint.identity.serial
                   && $0.authorization == .authorized
           }) {
            self.verifiedLegacyEndpoint = nil
        }
        if let selectedEndpointSerial,
           !endpoints.contains(where: { $0.identity.serial == selectedEndpointSerial }) {
            self.selectedEndpointSerial = nil
        }
        notices[.discovery] = nil
    }

    public func isCurrent(_ token: ConnectionOperationToken) -> Bool {
        operationGenerations[token.scope] == token.generation
    }

    private func isVerifiedSecure(_ endpoint: ADBEndpoint) -> Bool {
        guard endpoint.route == .secureWirelessDebugging else { return false }
        if case .secureServiceObservation = endpoint.provenance {
            return true
        }
        return false
    }

    private func isVerifiedLegacy(_ endpoint: ADBEndpoint) -> Bool {
        guard endpoint.route == .legacyWirelessUntilRestart else { return false }
        if case let .appInitiatedLegacyTransition(_, wirelessSerial) = endpoint.provenance {
            return endpoint.identity.serial == wirelessSerial
        }
        return false
    }
}

public struct ConnectionOperationToken: Equatable, Sendable {
    public let scope: ConnectionNoticeScope
    public let generation: UInt64

    public init(scope: ConnectionNoticeScope, generation: UInt64) {
        self.scope = scope
        self.generation = generation
    }
}

public enum ConnectionNoticeScope: Hashable, Sendable {
    case discovery
    case wirelessDiscovery
    case wirelessSetup
    case mirroring
}

public enum ConnectionNoticeKind: Equatable, Sendable {
    case progress
    case success
    case warning
    case failure
}

public enum ConnectionRecoveryAction: Equatable, Sendable {
    case refresh
    case retryWirelessSetup
    case reconnectMirror

    public var buttonLabel: String {
        switch self {
        case .refresh: "Refresh Connections"
        case .retryWirelessSetup: "Open Wireless Setup"
        case .reconnectMirror: "Reconnect Mirror"
        }
    }
}

public struct ConnectionNotice: Equatable, Sendable {
    public let scope: ConnectionNoticeScope
    public let kind: ConnectionNoticeKind
    public let message: String
    public let recovery: ConnectionRecoveryAction?

    public init(
        scope: ConnectionNoticeScope,
        kind: ConnectionNoticeKind,
        message: String,
        recovery: ConnectionRecoveryAction? = nil
    ) {
        self.scope = scope
        self.kind = kind
        self.message = message
        self.recovery = recovery
    }
}

public struct ADBEndpoint: Equatable, Identifiable, Sendable {
    public let identity: DeviceIdentity
    public let authorization: DeviceConnectionState
    public let route: ConnectionRoute
    public let provenance: ConnectionProvenance

    public var id: String { identity.serial }

    public init(
        identity: DeviceIdentity,
        authorization: DeviceConnectionState,
        route: ConnectionRoute,
        provenance: ConnectionProvenance
    ) {
        self.identity = identity
        self.authorization = authorization
        self.route = route
        self.provenance = provenance
    }
}

public enum ConnectionRoute: Equatable, Sendable {
    case directUSB
    case secureWirelessDebugging
    case legacyWirelessUntilRestart
    case unclassifiedWireless
    case emulator

    public var devicePresentationPriority: Int {
        switch self {
        case .legacyWirelessUntilRestart: 0
        case .secureWirelessDebugging: 1
        case .directUSB: 2
        case .emulator: 3
        case .unclassifiedWireless: 4
        }
    }
}

public enum ConnectionProvenance: Equatable, Sendable {
    case adbUSBObservation
    case secureServiceObservation(serviceName: String)
    case appInitiatedLegacyTransition(sourceUSBSerial: String, wirelessSerial: String)
    case emulatorObservation
    case unverified
}

public enum ConnectionCoordinatorEvent: Sendable {
    case discoveryUpdated(
        endpoints: [ADBEndpoint],
        nearbySecureEndpointCount: Int,
        pairingAvailable: Bool
    )
    case discoveryCompleted(
        token: ConnectionOperationToken,
        endpoints: [ADBEndpoint],
        nearbySecureEndpointCount: Int,
        pairingAvailable: Bool
    )
    case discoveryFailed(token: ConnectionOperationToken, message: String)
    case legacySetupStarted(sourceUSBSerial: String)
    case legacySetupFailed(sourceUSBSerial: String)
    case legacySetupCompleted(sourceUSBSerial: String, wirelessIdentity: DeviceIdentity)
    case legacyTurnedOff(wirelessSerial: String)
    case mirroringStarted(endpointSerial: String)
    case mirroringStopped
    case operationFailed(
        scope: ConnectionNoticeScope,
        message: String,
        recovery: ConnectionRecoveryAction?
    )
    case noticeUpdated(ConnectionNotice)
    case noticeCleared(ConnectionNoticeScope)
    case endpointSelected(serial: String)
}
