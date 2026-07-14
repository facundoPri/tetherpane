public enum DeviceRecordID: Hashable, Codable, Sendable {
    case usb(serial: String)
    case secureService(name: String)
    case emulator(serial: String)
    case transientEndpoint(serial: String)

    public var stableDescription: String {
        switch self {
        case let .usb(serial): "usb:\(serial)"
        case let .secureService(name): "secure-service:\(name)"
        case let .emulator(serial): "emulator:\(serial)"
        case let .transientEndpoint(serial): "transient:\(serial)"
        }
    }

    public var isPersistent: Bool {
        if case .transientEndpoint = self { return false }
        return true
    }
}

public enum SavedConnectionRoute: String, Codable, Equatable, Sendable {
    case usbC
    case secureWiFi
    case legacyWiFiUntilRestart
    case emulator
    case unverifiedWiFi
}

public enum DevicePresence: Equatable, Sendable {
    case connected(route: SavedConnectionRoute)
    case authorizationRequired
    case locallyDisconnected(lastRoute: SavedConnectionRoute)
    case offline(lastRoute: SavedConnectionRoute)
}

public struct SavedDeviceRecord: Codable, Equatable, Sendable {
    public let id: DeviceRecordID
    public var displayName: String
    public var lastRoute: SavedConnectionRoute
    public var isLocallyDisconnected: Bool

    public init(
        id: DeviceRecordID,
        displayName: String,
        lastRoute: SavedConnectionRoute,
        isLocallyDisconnected: Bool = false
    ) {
        precondition(id.isPersistent, "Transient endpoints cannot become Saved Devices")
        self.id = id
        self.displayName = displayName
        self.lastRoute = lastRoute
        self.isLocallyDisconnected = isLocallyDisconnected
    }
}

public struct DeviceListItem: Equatable, Identifiable, Sendable {
    public let id: DeviceRecordID
    public let displayName: String
    public let presence: DevicePresence
    public let endpoints: [ADBEndpoint]
    public let isSaved: Bool

    public init(
        id: DeviceRecordID,
        displayName: String,
        presence: DevicePresence,
        endpoints: [ADBEndpoint],
        isSaved: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.presence = presence
        self.endpoints = endpoints
        self.isSaved = isSaved
    }
}

public struct DeviceDirectoryPresentation: Equatable, Sendable {
    public let connected: [DeviceListItem]
    public let offline: [DeviceListItem]

    public init(connected: [DeviceListItem], offline: [DeviceListItem]) {
        self.connected = connected
        self.offline = offline
    }
}

public struct DeviceDirectory: Sendable {
    private var records: [DeviceRecordID: SavedDeviceRecord]
    private var sessionSuppressedTransientIDs: Set<DeviceRecordID>

    public init(savedRecords: [SavedDeviceRecord] = []) {
        records = [:]
        for record in savedRecords where record.id.isPersistent {
            records[record.id] = record
        }
        sessionSuppressedTransientIDs = []
    }

    public var savedRecords: [SavedDeviceRecord] {
        records.values.sorted { $0.id.stableDescription < $1.id.stableDescription }
    }

    @discardableResult
    public mutating func observe(endpoints: [ADBEndpoint]) -> DeviceDirectoryPresentation {
        let grouped = Dictionary(grouping: endpoints, by: recordID(for:))
        var connected: [DeviceListItem] = []
        var observedOffline: [DeviceListItem] = []
        var observedPersistentIDs = Set<DeviceRecordID>()

        for (id, groupedEndpoints) in grouped {
            guard let endpoint = preferredEndpoint(in: groupedEndpoints) else { continue }
            let route = savedRoute(for: endpoint)
            if id.isPersistent {
                observedPersistentIDs.insert(id)
                var record = records[id] ?? SavedDeviceRecord(
                    id: id,
                    displayName: endpoint.identity.displayName,
                    lastRoute: route
                )
                record.displayName = endpoint.identity.displayName
                record.lastRoute = route
                records[id] = record

                if record.isLocallyDisconnected {
                    continue
                }
            } else if sessionSuppressedTransientIDs.contains(id) {
                continue
            }

            let hasAuthorizedEndpoint = groupedEndpoints.contains {
                $0.authorization == .authorized
            }
            let authorizationRequired = groupedEndpoints.contains {
                $0.authorization == .unauthorized
            } && !hasAuthorizedEndpoint
            if !hasAuthorizedEndpoint, !authorizationRequired {
                observedOffline.append(
                    DeviceListItem(
                        id: id,
                        displayName: endpoint.identity.displayName,
                        presence: .offline(lastRoute: route),
                        endpoints: groupedEndpoints.sorted {
                            $0.identity.serial < $1.identity.serial
                        },
                        isSaved: id.isPersistent
                    )
                )
                continue
            }
            connected.append(
                DeviceListItem(
                    id: id,
                    displayName: endpoint.identity.displayName,
                    presence: authorizationRequired
                        ? .authorizationRequired
                        : .connected(route: route),
                    endpoints: groupedEndpoints.sorted {
                        $0.identity.serial < $1.identity.serial
                    },
                    isSaved: id.isPersistent
                )
            )
        }

        let savedOffline = records.values.compactMap { record -> DeviceListItem? in
            if observedPersistentIDs.contains(record.id), !record.isLocallyDisconnected {
                return nil
            }
            return DeviceListItem(
                id: record.id,
                displayName: record.displayName,
                presence: record.isLocallyDisconnected
                    ? .locallyDisconnected(lastRoute: record.lastRoute)
                    : .offline(lastRoute: record.lastRoute),
                endpoints: [],
                isSaved: true
            )
        }

        return DeviceDirectoryPresentation(
            connected: sorted(connected),
            offline: sorted(observedOffline + savedOffline)
        )
    }

    public mutating func markLocallyDisconnected(_ id: DeviceRecordID) {
        if id.isPersistent {
            records[id]?.isLocallyDisconnected = true
        } else {
            sessionSuppressedTransientIDs.insert(id)
        }
    }

    public mutating func markConnected(_ id: DeviceRecordID) {
        records[id]?.isLocallyDisconnected = false
        sessionSuppressedTransientIDs.remove(id)
    }

    @discardableResult
    public mutating func forget(_ id: DeviceRecordID) -> Bool {
        records.removeValue(forKey: id) != nil
    }

    public func isLocallyDisconnected(_ id: DeviceRecordID) -> Bool {
        records[id]?.isLocallyDisconnected == true
            || sessionSuppressedTransientIDs.contains(id)
    }

    public func recordID(for endpoint: ADBEndpoint) -> DeviceRecordID {
        switch endpoint.provenance {
        case .adbUSBObservation:
            return .usb(serial: endpoint.identity.serial)
        case let .secureServiceObservation(serviceName):
            return .secureService(name: serviceName)
        case let .appInitiatedLegacyTransition(sourceUSBSerial, _):
            return .usb(serial: sourceUSBSerial)
        case .emulatorObservation:
            return .emulator(serial: endpoint.identity.serial)
        case .unverified:
            return .transientEndpoint(serial: endpoint.identity.serial)
        }
    }

    private func savedRoute(for endpoint: ADBEndpoint) -> SavedConnectionRoute {
        switch endpoint.route {
        case .directUSB: .usbC
        case .secureWirelessDebugging: .secureWiFi
        case .legacyWirelessUntilRestart: .legacyWiFiUntilRestart
        case .emulator: .emulator
        case .unclassifiedWireless: .unverifiedWiFi
        }
    }

    private func preferredEndpoint(in endpoints: [ADBEndpoint]) -> ADBEndpoint? {
        endpoints.sorted { lhs, rhs in
            lhs.route.devicePresentationPriority
                < rhs.route.devicePresentationPriority
        }.first
    }

    private func sorted(_ items: [DeviceListItem]) -> [DeviceListItem] {
        items.sorted {
            let nameOrder = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            if nameOrder == .orderedSame {
                return $0.id.stableDescription < $1.id.stableDescription
            }
            return nameOrder == .orderedAscending
        }
    }
}
