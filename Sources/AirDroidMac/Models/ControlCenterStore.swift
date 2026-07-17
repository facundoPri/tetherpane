import AirDroidDomain
import AirDroidScrcpy
import Foundation
import Observation
import OSLog
import TetherPaneUIFixtureSupport

private func performOffMain<T: Sendable>(
    _ operation: @escaping @Sendable () throws -> T
) async throws -> T {
    let worker = Task.detached(priority: .userInitiated, operation: operation)
    return try await withTaskCancellationHandler {
        try await worker.value
    } onCancel: {
        worker.cancel()
    }
}

enum DeviceSidebarSelection: Hashable {
    case device(String)
    case wirelessCandidate(String)
}

enum ControlCenterNavigationSelection: Hashable {
    case device(DeviceRecordID)
    case usbAutomatic
    case wifiOnly
}

private struct DiscoveryTelemetrySummary: Equatable {
    let authorizedCount: Int
    let deviceCount: Int
    let pairingCandidateCount: Int
    let wirelessCandidateCount: Int
}

private struct PendingLegacyVerification {
    let sourceUSB: DeviceIdentity
    let wirelessSerial: String
    let operationToken: ConnectionOperationToken
}

private struct PendingSecureVerification {
    let wirelessSerial: String
    let serviceName: String
    let operationToken: ConnectionOperationToken
}

private struct PendingPairingVerification {
    let candidate: PairingCandidate
    let operationToken: ConnectionOperationToken
}

private struct PreparedMirroring {
    let configuration: MirroringConfiguration
    let recordingURL: URL?
    let warning: String?
}

protocol LegacyRiskPersisting: Sendable {
    func load() -> String?
    func save(sourceUSBSerial: String)
    func clear()
}

struct UserDefaultsLegacyRiskStore: LegacyRiskPersisting {
    // Keep the pre-public codename keys so existing local beta state migrates without data loss.
    private static let key = "AirDroid.possibleLegacySourceUSBSerial.v1"
    private static let unsafeLegacyMappingKey = "AirDroid.verifiedLegacySources.v1"

    func load() -> String? {
        UserDefaults.standard.removeObject(forKey: Self.unsafeLegacyMappingKey)
        return UserDefaults.standard.string(forKey: Self.key)
    }

    func save(sourceUSBSerial: String) {
        UserDefaults.standard.set(sourceUSBSerial, forKey: Self.key)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}

struct EphemeralLegacyRiskStore: LegacyRiskPersisting {
    func load() -> String? { nil }
    func save(sourceUSBSerial: String) {}
    func clear() {}
}

enum LegacyRiskStoreFactory {
    static func make(for fixture: UIFixture?) -> any LegacyRiskPersisting {
        if fixture == nil {
            return UserDefaultsLegacyRiskStore()
        }
        return EphemeralLegacyRiskStore()
    }
}

protocol DeviceDirectoryPersisting: Sendable {
    func load() -> [SavedDeviceRecord]
    func save(_ records: [SavedDeviceRecord])
}

struct UserDefaultsDeviceDirectoryStore: DeviceDirectoryPersisting {
    // Keep the pre-public codename key so saved-device rows survive the product rename.
    private static let key = "AirDroid.savedDeviceDirectory.v1"

    func load() -> [SavedDeviceRecord] {
        guard let data = UserDefaults.standard.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([SavedDeviceRecord].self, from: data)) ?? []
    }

    func save(_ records: [SavedDeviceRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}

struct EphemeralDeviceDirectoryStore: DeviceDirectoryPersisting {
    func load() -> [SavedDeviceRecord] { [] }
    func save(_ records: [SavedDeviceRecord]) {}
}

enum DeviceDirectoryStoreFactory {
    static func make(for fixture: UIFixture?) -> any DeviceDirectoryPersisting {
        if fixture == nil {
            return UserDefaultsDeviceDirectoryStore()
        }
        return EphemeralDeviceDirectoryStore()
    }
}

@MainActor
@Observable
final class ControlCenterStore {
    private let discovery: any DeviceDiscovery
    private let pairing: any PairingClient
    private let wirelessConnection: any WirelessConnectionClient
    private let mirroring: any MirroringEngine
    private let legacyRiskStore: any LegacyRiskPersisting
    private let deviceDirectoryStore: any DeviceDirectoryPersisting
    private let logger = Logger(subsystem: "com.facundopri.tetherpane", category: "Connection")
    private var connectionCoordinator = ConnectionCoordinator()
    private var endpointClassifier: ConnectionEndpointClassifier
    private var deviceDirectory: DeviceDirectory
    private var possibleLegacySourceUSBSerial: String?

    var devices: [DiscoveredDevice] = []
    var pairingCandidates: [PairingCandidate] = []
    var wirelessConnectionCandidates: [WirelessConnectionCandidate] = []
    var sidebarSelection: DeviceSidebarSelection?
    var navigationSelection: ControlCenterNavigationSelection?
    private(set) var deviceDirectoryPresentation = DeviceDirectoryPresentation(
        connected: [],
        offline: []
    )
    private(set) var disconnectingDeviceID: DeviceRecordID?
    var selectedPreset: MirrorPreset = .responsive
    var audioEnabled = true
    var recordNextSession = false
    var isAdvancedVisible = false
    var discoveryMessage: String?
    var sessionMessage: String?
    var deviceManagementMessage: String?
    var sessionState: MirroringSessionState = .idle
    var diagnostics = ScrcpyDiagnostics()
    var effectiveInvocation: ScrcpyInvocation?
    var pairingMessage: String?
    var wirelessConnectionMessage: String?
    private var pendingPairingVerification: PendingPairingVerification?
    private var lastDiscoveryTelemetrySummary: DiscoveryTelemetrySummary?
    private var discoveryTask: Task<Void, Never>?
    private var wirelessTask: Task<Void, Never>?
    private var deviceManagementTask: Task<Void, Never>?
    private var mirroringTask: Task<Void, Never>?
    private var isLegacySetupInFlight = false
    private(set) var isOpeningDeveloperOptions = false
    private var pendingSecureVerification: PendingSecureVerification?
    private var pendingLegacyVerification: PendingLegacyVerification?
    let resolvedADBPath: String
    let resolvedScrcpyPath: String

    init(
        discovery: any DeviceDiscovery,
        pairing: any PairingClient,
        wirelessConnection: any WirelessConnectionClient,
        mirroring: any MirroringEngine,
        resolvedADBPath: String? = DeveloperToolPathResolver.adbPath(),
        resolvedScrcpyPath: String? = DeveloperToolPathResolver.scrcpyPath(),
        uiFixture: UIFixture? = nil,
        legacyRiskStore: any LegacyRiskPersisting = UserDefaultsLegacyRiskStore(),
        deviceDirectoryStore: any DeviceDirectoryPersisting = UserDefaultsDeviceDirectoryStore()
    ) {
        self.discovery = discovery
        self.pairing = pairing
        self.wirelessConnection = wirelessConnection
        self.mirroring = mirroring
        self.legacyRiskStore = legacyRiskStore
        self.deviceDirectoryStore = deviceDirectoryStore
        endpointClassifier = ConnectionEndpointClassifier()
        deviceDirectory = DeviceDirectory(savedRecords: deviceDirectoryStore.load())
        possibleLegacySourceUSBSerial = legacyRiskStore.load()
        self.resolvedADBPath = resolvedADBPath ?? "Unavailable"
        self.resolvedScrcpyPath = resolvedScrcpyPath ?? "Unavailable"
        self.mirroring.stateDidChange = { [weak self] state in
            self?.sessionState = state
            if case let .mirroring(device) = state {
                self?.connectionCoordinator.send(
                    .mirroringStarted(endpointSerial: device.serial)
                )
            } else if case .stopped = state {
                self?.connectionCoordinator.send(.mirroringStopped)
            } else if case let .failed(message) = state {
                self?.sessionMessage = message
                self?.connectionCoordinator.send(.mirroringStopped)
                self?.connectionCoordinator.send(
                    .operationFailed(
                        scope: .mirroring,
                        message: message,
                        recovery: .reconnectMirror
                    )
                )
            }
        }
        self.mirroring.diagnosticsDidChange = { [weak self] diagnostics in
            self?.diagnostics = diagnostics
        }
        installUIFixture(uiFixture)
    }

    private func installUIFixture(_ fixture: UIFixture?) {
        guard let fixture else { return }
        let seed = fixture.scenario.storeSeed

        if !seed.savedRecords.isEmpty {
            deviceDirectory = DeviceDirectory(savedRecords: seed.savedRecords)
            deviceDirectoryPresentation = deviceDirectory.observe(endpoints: [])
        }
        if let selectedSavedRecordID = seed.selectedSavedRecordID {
            navigationSelection = .device(selectedSavedRecordID)
        }
        guard let legacyScenario = seed.legacyScenario else { return }

        possibleLegacySourceUSBSerial = nil
        let sourceUSB: DiscoveredDevice
        switch legacyScenario {
        case let .enabling(device), let .safeToUnplug(device, _):
            sourceUSB = device
        }
        devices = [sourceUSB]
        sidebarSelection = .device(sourceUSB.id)

        switch legacyScenario {
        case .enabling:
            publishFixtureDiscovery()
            connectionCoordinator.send(
                .legacySetupStarted(sourceUSBSerial: sourceUSB.identity.serial)
            )
            isLegacySetupInFlight = true
            wirelessConnectionMessage = "Enabling Wi-Fi while the USB cable remains attached…"
        case let .safeToUnplug(_, wireless):
            devices.append(wireless)
            recordLegacyProvenance(
                sourceUSBSerial: sourceUSB.identity.serial,
                wirelessSerial: wireless.identity.serial
            )
            publishFixtureDiscovery()
            connectionCoordinator.send(
                .legacySetupStarted(sourceUSBSerial: sourceUSB.identity.serial)
            )
            connectionCoordinator.send(
                .legacySetupCompleted(
                    sourceUSBSerial: sourceUSB.identity.serial,
                    wirelessIdentity: wireless.identity
                )
            )
            sidebarSelection = .device(wireless.id)
            wirelessConnectionMessage = "Connected over Wi-Fi. You can unplug USB now; repeat this setup after the phone restarts."
        }
    }

    private func publishFixtureDiscovery() {
        connectionCoordinator.send(
            .discoveryUpdated(
                endpoints: devices.map {
                    endpointClassifier.endpoint(
                        for: $0,
                        wirelessCandidates: []
                    )
                },
                nearbySecureEndpointCount: 0,
                pairingAvailable: false
            )
        )
    }

    func refreshDevices(showProgress: Bool = true) {
        logger.debug("device discovery poll requested")
        discoveryTask?.cancel()
        let token = connectionCoordinator.beginOperation(
            scope: .discovery,
            message: "Refreshing connections…",
            showsProgress: showProgress
        )
        let discovery = self.discovery
        discoveryTask = Task { [weak self] in
            do {
                let snapshot = try await performOffMain {
                    try discovery.discover()
                }
                guard !Task.isCancelled else { return }
                self?.applyDiscoverySnapshot(snapshot, token: token)
            } catch {
                guard !Task.isCancelled else { return }
                self?.applyDiscoveryFailure(error, token: token)
            }
        }
    }

    var isMirroring: Bool {
        if case .mirroring = sessionState {
            true
        } else {
            false
        }
    }

    var isStartingMirroring: Bool {
        if case .starting = sessionState {
            true
        } else {
            false
        }
    }

    var isCompletingLegacySetup: Bool {
        isLegacySetupInFlight || pendingLegacyVerification != nil
    }

    var canTurnOffLegacyRisk: Bool { !isLegacySetupInFlight }

    var selectedDevice: DiscoveredDevice? {
        guard case let .device(id) = sidebarSelection else {
            return nil
        }
        return devices.first(where: { $0.id == id })
    }

    var presentation: ControlCenterPresentation {
        connectionCoordinator.presentation
    }

    var presentedEndpoint: ADBEndpoint? {
        presentation.workspace.endpoint
    }

    var presentedDevice: DiscoveredDevice? {
        guard let presentedEndpoint else { return nil }
        return devices.first(where: { $0.identity.serial == presentedEndpoint.identity.serial })
            ?? (presentedEndpoint.route == .legacyWirelessUntilRestart
                ? DiscoveredDevice(
                    identity: presentedEndpoint.identity,
                    state: presentedEndpoint.authorization,
                    transport: .wireless
                )
                : nil)
    }

    var distinctUSBDevices: [DiscoveredDevice] {
        devices.filter { $0.transport == .usb }
    }

    var hasDistinguishableUSBChoices: Bool {
        let names = Set(distinctUSBDevices.map(\.identity.displayName))
        return distinctUSBDevices.count > 1 && names.count == distinctUSBDevices.count
    }

    var requiresUSBDisambiguation: Bool {
        distinctUSBDevices.count > 1 && !hasDistinguishableUSBChoices
    }

    var selectedAuthorizedUSBDevice: DiscoveredDevice? {
        guard !requiresUSBDisambiguation else { return nil }
        if let selectedDevice,
           selectedDevice.transport == .usb,
           selectedDevice.state == .authorized {
            return selectedDevice
        }
        let authorizedUSBDevices = distinctUSBDevices.filter { $0.state == .authorized }
        return authorizedUSBDevices.count == 1 ? authorizedUSBDevices[0] : nil
    }

    func hasPossibleLegacyRisk(for device: DiscoveredDevice) -> Bool {
        device.transport == .usb
            && device.identity.serial == possibleLegacySourceUSBSerial
    }

    func selectDevice(_ device: DiscoveredDevice) {
        sidebarSelection = .device(device.id)
        connectionCoordinator.send(.endpointSelected(serial: device.identity.serial))
    }

    var connectedDeviceItems: [DeviceListItem] {
        deviceDirectoryPresentation.connected
    }

    var offlineDeviceItems: [DeviceListItem] {
        deviceDirectoryPresentation.offline
    }

    var selectedDeviceItem: DeviceListItem? {
        guard case let .device(id) = navigationSelection else { return nil }
        return (connectedDeviceItems + offlineDeviceItems).first(where: { $0.id == id })
    }

    var selectedAuthorizedEndpoint: ADBEndpoint? {
        guard let item = selectedDeviceItem,
              connectedDeviceItems.contains(where: { $0.id == item.id }),
              let endpoint = preferredEndpoint(for: item),
              endpoint.authorization == .authorized
        else { return nil }
        return endpoint
    }

    var canMirrorSelectedDevice: Bool {
        selectedAuthorizedEndpoint != nil
            && !isMirroring
            && !isStartingMirroring
    }

    func activateNavigationSelection() {
        guard let item = selectedDeviceItem else {
            sidebarSelection = nil
            return
        }
        guard let endpoint = preferredEndpoint(for: item) else {
            sidebarSelection = nil
            return
        }
        if isMirroring,
           let activeEndpoint = presentedEndpoint,
           !item.endpoints.contains(where: {
               $0.identity.serial == activeEndpoint.identity.serial
           }) {
            navigationSelection = .device(
                deviceDirectory.recordID(for: activeEndpoint)
            )
            return
        }
        if requiresUSBDisambiguation,
           case .usb = item.id {
            return
        }
        sidebarSelection = .device(endpoint.identity.serial)
        connectionCoordinator.send(.endpointSelected(serial: endpoint.identity.serial))
    }

    func reconnectCandidate(for item: DeviceListItem) -> WirelessConnectionCandidate? {
        guard case let .secureService(serviceName) = item.id else { return nil }
        return wirelessConnectionCandidates.first(where: { $0.serviceName == serviceName })
    }

    func canForget(_ item: DeviceListItem) -> Bool {
        guard item.isSaved,
              offlineDeviceItems.contains(where: { $0.id == item.id })
        else { return false }
        return !classifiedEndpoints().contains(where: {
            deviceDirectory.recordID(for: $0) == item.id
        })
    }

    func forget(_ item: DeviceListItem) {
        guard canForget(item), deviceDirectory.forget(item.id) else { return }
        persistDeviceDirectory()
        updateDeviceDirectoryFromCurrentObservation()
        navigationSelection = connectedDeviceItems.first.map {
            .device($0.id)
        } ?? .usbAutomatic
        deviceManagementMessage = "Removed \(item.displayName) from this Mac's device list. Android settings were not changed."
    }

    func disconnect(_ item: DeviceListItem) {
        guard disconnectingDeviceID == nil else { return }
        let endpoints = item.endpoints.filter {
            $0.route == .secureWirelessDebugging || $0.route == .unclassifiedWireless
        }
        guard !endpoints.isEmpty,
              endpoints.count == item.endpoints.count
        else {
            deviceManagementMessage = "This route cannot use ordinary disconnect. Unplug USB, or use Turn Off for USB-assisted Wi-Fi."
            return
        }

        disconnectingDeviceID = item.id
        deviceManagementMessage = "Disconnecting \(item.displayName) on this Mac…"
        cancelWirelessTask()
        deviceManagementTask?.cancel()
        let wirelessConnection = self.wirelessConnection
        let mirroring = self.mirroring
        let shouldStopMirroring = isMirroring && endpoints.contains(where: {
            $0.identity.serial == presentedEndpoint?.identity.serial
        })
        deviceManagementTask = Task { [weak self] in
            defer {
                if self?.disconnectingDeviceID == item.id {
                    self?.disconnectingDeviceID = nil
                }
                self?.deviceManagementTask = nil
            }
            do {
                if shouldStopMirroring {
                    await mirroring.stop()
                }
                try await performOffMain {
                    for endpoint in endpoints {
                        try wirelessConnection.disconnect(endpoint: endpoint)
                    }
                }
                guard let self, !Task.isCancelled else { return }
                self.deviceDirectory.markLocallyDisconnected(item.id)
                self.persistDeviceDirectory()
                self.updateDeviceDirectoryFromCurrentObservation()
                let isVerifiedSecure = endpoints.allSatisfy {
                    $0.route == .secureWirelessDebugging
                }
                self.deviceManagementMessage = isVerifiedSecure
                    ? "Disconnected on this Mac. Android still remembers this Mac, so you can reconnect without pairing while Wireless Debugging remains enabled."
                    : "Disconnected the exact unverified endpoint for this app session. Its route and Android authorization lifetime are unknown."
                self.connectionCoordinator.send(
                    .noticeUpdated(
                        ConnectionNotice(
                            scope: .wirelessSetup,
                            kind: .success,
                            message: isVerifiedSecure
                                ? "Disconnected on this Mac. Android authorization is unchanged."
                                : "Disconnected the exact unverified endpoint for this session."
                        )
                    )
                )
                self.refreshDevices(showProgress: false)
            } catch {
                guard let self else { return }
                if Task.isCancelled {
                    self.deviceManagementMessage = "Disconnect was interrupted. Refresh before trying again."
                    return
                }
                self.deviceManagementMessage = error.localizedDescription
                self.connectionCoordinator.send(
                    .operationFailed(
                        scope: .wirelessSetup,
                        message: error.localizedDescription,
                        recovery: .refresh
                    )
                )
            }
        }
    }

    var selectedWirelessCandidate: WirelessConnectionCandidate? {
        guard case let .wirelessCandidate(id) = sidebarSelection else {
            return nil
        }
        return visibleWirelessConnectionCandidates.first(where: { $0.id == id })
    }

    var visibleWirelessConnectionCandidates: [WirelessConnectionCandidate] {
        visibleWirelessCandidates(
            devices: devices,
            candidates: wirelessConnectionCandidates
        )
    }

    var sessionLabel: String {
        switch sessionState {
        case .idle: "Ready"
        case .starting: "Starting"
        case .mirroring: "Mirroring"
        case .stopped: "Stopped"
        case .failed: "Needs attention"
        }
    }

    func toggleMirroring() {
        guard let endpoint = selectedAuthorizedEndpoint else {
            sessionMessage = "Select an authorized Android ADB endpoint before mirroring."
            return
        }
        toggleMirroring(endpoint: endpoint)
    }

    func toggleMirroring(endpoint: ADBEndpoint) {
        if isMirroring {
            stopMirroring()
            return
        }

        guard let device = devices.first(where: {
            $0.identity.serial == endpoint.identity.serial && $0.state == .authorized
        }) else {
            sessionMessage = "That ADB endpoint is no longer authorized. Refresh connections before mirroring."
            connectionCoordinator.send(
                .operationFailed(
                    scope: .mirroring,
                    message: sessionMessage ?? "The requested ADB endpoint is unavailable.",
                    recovery: .refresh
                )
            )
            return
        }

        sidebarSelection = .device(device.id)
        connectionCoordinator.send(.endpointSelected(serial: device.identity.serial))
        guard let prepared = prepareMirroring(for: device) else { return }

        mirroringTask?.cancel()
        _ = connectionCoordinator.beginOperation(
            scope: .mirroring,
            message: "Starting stock scrcpy for the selected ADB endpoint…"
        )
        mirroringTask = Task { [weak self] in
            await self?.runMirroring(prepared)
        }
    }

    func stopMirroring() {
        mirroringTask?.cancel()
        _ = connectionCoordinator.beginOperation(
            scope: .mirroring,
            message: "Stopping the current scrcpy session…"
        )
        let mirroring = self.mirroring
        mirroringTask = Task { [weak self] in
            await mirroring.stop()
            guard !Task.isCancelled else { return }
            self?.sessionState = mirroring.state
            self?.sessionMessage = "Mirroring stopped."
        }
    }

    func reconnect() {
        guard let endpoint = selectedAuthorizedEndpoint,
              let device = devices.first(where: {
                  $0.identity.serial == endpoint.identity.serial && $0.state == .authorized
              }),
              let prepared = prepareMirroring(for: device)
        else {
            let message = "The previous ADB endpoint is no longer authorized. Refresh connections before reconnecting."
            sessionMessage = message
            connectionCoordinator.send(
                .operationFailed(
                    scope: .mirroring,
                    message: message,
                    recovery: .refresh
                )
            )
            return
        }

        mirroringTask?.cancel()
        _ = connectionCoordinator.beginOperation(
            scope: .mirroring,
            message: "Reconnecting stock scrcpy to the same ADB endpoint…"
        )
        let mirroring = self.mirroring
        mirroringTask = Task { [weak self] in
            await mirroring.stop()
            guard !Task.isCancelled else { return }
            await self?.runMirroring(prepared)
        }
    }

    private func prepareMirroring(for device: DiscoveredDevice) -> PreparedMirroring? {
        let recordingURL: URL?
        let warning: String?
        if recordNextSession {
            do {
                recordingURL = try RecordingDestination.nextURL()
                warning = nil
            } catch {
                let message = "Recording could not be prepared, so this session will start without recording."
                recordNextSession = false
                sessionMessage = message
                recordingURL = nil
                warning = message
            }
        } else {
            recordingURL = nil
            warning = nil
        }

        return PreparedMirroring(
            configuration: MirroringConfiguration(
                device: device.identity,
                preset: selectedPreset,
                audioEnabled: audioEnabled,
                recordingURL: recordingURL
            ),
            recordingURL: recordingURL,
            warning: warning
        )
    }

    private func runMirroring(_ prepared: PreparedMirroring) async {
        do {
            effectiveInvocation = try await mirroring.start(
                configuration: prepared.configuration
            )
            guard !Task.isCancelled else {
                await mirroring.stop()
                return
            }
            sessionState = mirroring.state
            diagnostics = mirroring.diagnostics
            if let warning = prepared.warning {
                connectionCoordinator.send(
                    .noticeUpdated(
                        ConnectionNotice(
                            scope: .mirroring,
                            kind: .warning,
                            message: warning
                        )
                    )
                )
            } else if prepared.recordingURL != nil {
                sessionMessage = "Recording will be written when this scrcpy session stops."
            }
        } catch is CancellationError {
            return
        } catch {
            sessionState = mirroring.state
            sessionMessage = error.localizedDescription
        }
    }

    func pair(candidate: PairingCandidate, code: String) {
        guard canStartWirelessAction() else { return }
        logger.info("wireless pairing requested")
        cancelWirelessTask()
        let operationToken = connectionCoordinator.beginOperation(
            scope: .wirelessSetup,
            message: "Pairing securely with Android…"
        )
        pairingMessage = "Pairing securely with Android…"
        let pairing = self.pairing
        wirelessTask = Task { [weak self] in
            do {
                try await performOffMain {
                    try pairing.pair(candidate: candidate, code: code)
                }
                guard !Task.isCancelled else { return }
                self?.pairingMessage = "Paired successfully. Waiting for this phone's Wi-Fi connection service."
                self?.connectionCoordinator.send(
                    .noticeUpdated(
                        ConnectionNotice(
                            scope: .wirelessSetup,
                            kind: .success,
                            message: "Secure pairing succeeded. Verifying the exact Wi-Fi connection…"
                        )
                    )
                )
                self?.logger.info("wireless pairing completed")
                self?.finishPairing(
                    candidate: candidate,
                    operationToken: operationToken
                )
            } catch {
                guard !Task.isCancelled else { return }
                self?.pairingMessage = error.localizedDescription
                self?.connectionCoordinator.send(
                    .operationFailed(
                        scope: .wirelessSetup,
                        message: error.localizedDescription,
                        recovery: .retryWirelessSetup
                    )
                )
                self?.logger.error("wireless pairing failed")
            }
        }
    }

    func connectWirelessly(candidate: WirelessConnectionCandidate) {
        guard canStartWirelessAction() else { return }
        logger.info("wireless connection requested")
        cancelWirelessTask()
        let operationToken = connectionCoordinator.beginOperation(
            scope: .wirelessSetup,
            message: "Connecting securely over Wi-Fi…"
        )
        wirelessConnectionMessage = "Connecting securely over Wi-Fi…"
        let wirelessConnection = self.wirelessConnection
        wirelessTask = Task { [weak self] in
            do {
                let connection = try await performOffMain {
                    try wirelessConnection.connect(candidate: candidate)
                }
                guard !Task.isCancelled else { return }
                self?.pendingSecureVerification = PendingSecureVerification(
                    wirelessSerial: connection.deviceSerial,
                    serviceName: candidate.serviceName,
                    operationToken: operationToken
                )
                self?.wirelessConnectionMessage = "ADB connected. Verifying the exact authorized endpoint…"
                self?.refreshDevices()
            } catch {
                guard !Task.isCancelled else { return }
                self?.wirelessConnectionMessage = error.localizedDescription
                self?.connectionCoordinator.send(
                    .operationFailed(
                        scope: .wirelessSetup,
                        message: error.localizedDescription,
                        recovery: .retryWirelessSetup
                    )
                )
                self?.logger.error("wireless connection failed")
            }
        }
    }

    func connectOverTCPIP(from device: DiscoveredDevice) {
        guard canStartWirelessAction() else { return }
        guard device.state == .authorized, device.transport == .usb else {
            wirelessConnectionMessage = "Connect and authorize this phone over USB before using the until-restart Wi-Fi setup."
            return
        }

        logger.info("USB-bootstrapped TCP/IP connection requested")
        wirelessConnectionMessage = "Enabling Wi-Fi on this USB connection…"
        cancelWirelessTask()
        let operationToken = connectionCoordinator.beginOperation(
            scope: .wirelessSetup,
            message: "Enabling Wi-Fi while the USB cable remains attached…"
        )
        connectionCoordinator.send(
            .legacySetupStarted(sourceUSBSerial: device.identity.serial)
        )
        isLegacySetupInFlight = true
        recordPossibleLegacyRisk(sourceUSBSerial: device.identity.serial)
        let wirelessConnection = self.wirelessConnection
        wirelessTask = Task { [weak self] in
            do {
                let connection = try await performOffMain {
                    try wirelessConnection.connectOverTCPIP(device: device.identity)
                }
                self?.isLegacySetupInFlight = false
                guard !Task.isCancelled else { return }
                self?.pendingLegacyVerification = PendingLegacyVerification(
                    sourceUSB: device.identity,
                    wirelessSerial: connection.deviceSerial,
                    operationToken: operationToken
                )
                self?.wirelessConnectionMessage = "Wi-Fi was enabled. Keep USB attached while TetherPane verifies the exact wireless endpoint…"
                self?.refreshDevices()
            } catch {
                self?.isLegacySetupInFlight = false
                let message = Task.isCancelled
                    ? "USB-assisted setup was interrupted after it may have opened an unencrypted listener. Keep USB attached and use Turn Off before unplugging."
                    : error.localizedDescription
                self?.wirelessConnectionMessage = message
                self?.connectionCoordinator.send(
                    .legacySetupFailed(sourceUSBSerial: device.identity.serial)
                )
                self?.connectionCoordinator.send(
                    .operationFailed(
                        scope: .wirelessSetup,
                        message: message,
                        recovery: .refresh
                    )
                )
                self?.logger.error("USB-bootstrapped TCP/IP connection failed")
            }
        }
    }

    func openDeveloperOptions(on device: DiscoveredDevice) {
        guard canStartWirelessAction() else { return }
        guard device.state == .authorized, device.transport == .usb else {
            wirelessConnectionMessage = "Connect and authorize this phone over USB before opening its Developer Options from the Mac."
            return
        }

        logger.info("Developer Options launch requested")
        cancelWirelessTask()
        let operationToken = connectionCoordinator.beginOperation(
            scope: .wirelessSetup,
            message: "Opening Developer Options on the selected USB phone…"
        )
        wirelessConnectionMessage = "Opening Developer Options on the selected USB phone…"
        isOpeningDeveloperOptions = true
        let wirelessConnection = self.wirelessConnection
        wirelessTask = Task { [weak self] in
            do {
                try await performOffMain {
                    try wirelessConnection.openDeveloperOptions(device: device.identity)
                }
                guard let self,
                      !Task.isCancelled,
                      self.connectionCoordinator.isCurrent(operationToken)
                else { return }
                self.isOpeningDeveloperOptions = false
                let message = "Developer Options opened on the phone. Android requires you to turn on Wireless debugging there manually."
                self.wirelessConnectionMessage = message
                self.connectionCoordinator.send(
                    .noticeUpdated(
                        ConnectionNotice(
                            scope: .wirelessSetup,
                            kind: .success,
                            message: message
                        )
                    )
                )
                self.logger.info("Developer Options launch completed")
            } catch {
                guard let self,
                      !Task.isCancelled,
                      self.connectionCoordinator.isCurrent(operationToken)
                else { return }
                self.isOpeningDeveloperOptions = false
                let message = error.localizedDescription
                self.wirelessConnectionMessage = message
                self.connectionCoordinator.send(
                    .operationFailed(
                        scope: .wirelessSetup,
                        message: message,
                        recovery: .retryWirelessSetup
                    )
                )
                self.logger.error("Developer Options launch failed")
            }
        }
    }

    func disableTCPIP(on device: DiscoveredDevice) {
        guard !isLegacySetupInFlight else {
            wirelessConnectionMessage = "Keep USB attached until the current ADB command finishes, then use Turn Off."
            return
        }
        pendingLegacyVerification = nil
        let endpoint = endpointClassifier.endpoint(
            for: device,
            wirelessCandidates: wirelessConnectionCandidates
        )
        let isVerifiedLegacyEndpoint = endpoint.route == .legacyWirelessUntilRestart
        let isPossibleLegacySource = hasPossibleLegacyRisk(for: device)
        guard device.state == .authorized,
              isVerifiedLegacyEndpoint || isPossibleLegacySource
        else {
            wirelessConnectionMessage = "Select the proven Wi-Fi · until restart endpoint, or reconnect its original USB phone, before turning off the listener."
            return
        }

        logger.info("USB-bootstrapped TCP/IP disablement requested")
        if isMirroring {
            stopMirroring()
        }
        cancelWirelessTask()
        _ = connectionCoordinator.beginOperation(
            scope: .wirelessSetup,
            message: "Turning off the unencrypted listener…"
        )
        let wirelessConnection = self.wirelessConnection
        wirelessTask = Task { [weak self] in
            do {
                try await performOffMain {
                    try wirelessConnection.disableTCPIP(endpoint: endpoint)
                }
                guard !Task.isCancelled else { return }
                self?.finishLegacyDisablement(device: device)
                self?.wirelessConnectionMessage = "USB-assisted Wi-Fi is off. Android's separate Wireless Debugging setting is unchanged. Connect USB again to re-enable this mode."
                self?.connectionCoordinator.send(
                    .noticeUpdated(
                        ConnectionNotice(
                            scope: .wirelessSetup,
                            kind: .success,
                            message: "USB-assisted Wi-Fi is off."
                        )
                    )
                )
                self?.refreshDevices()
                self?.logger.info("USB-bootstrapped TCP/IP disablement completed")
            } catch {
                guard !Task.isCancelled else { return }
                self?.wirelessConnectionMessage = error.localizedDescription
                self?.connectionCoordinator.send(
                    .operationFailed(
                        scope: .wirelessSetup,
                        message: error.localizedDescription,
                        recovery: .retryWirelessSetup
                    )
                )
                self?.logger.error("USB-bootstrapped TCP/IP disablement failed")
            }
        }
    }

    private func finishPairing(
        candidate: PairingCandidate,
        operationToken: ConnectionOperationToken
    ) {
        pendingPairingVerification = PendingPairingVerification(
            candidate: candidate,
            operationToken: operationToken
        )
        refreshDevices()
        if pendingPairingVerification != nil {
            wirelessConnectionMessage = "Pairing succeeded. Waiting for this phone's Wi-Fi connection service; no cable is required."
        }
    }

    private func cancelWirelessTask() {
        wirelessTask?.cancel()
        wirelessTask = nil
        isOpeningDeveloperOptions = false
    }

    private func canStartWirelessAction() -> Bool {
        guard disconnectingDeviceID == nil else {
            deviceManagementMessage = "Wait for the current disconnect to finish before starting another wireless action."
            return false
        }
        guard !isCompletingLegacySetup else {
            let message = "Keep the cable attached while USB-assisted Wi-Fi finishes. Other wireless actions are temporarily unavailable."
            wirelessConnectionMessage = message
            connectionCoordinator.send(
                .noticeUpdated(
                    ConnectionNotice(
                        scope: .wirelessSetup,
                        kind: .warning,
                        message: message
                    )
                )
            )
            return false
        }
        return true
    }

    private func applyDiscoverySnapshot(
        _ snapshot: DeviceDiscoverySnapshot,
        token: ConnectionOperationToken
    ) {
        let nextDevices = snapshot.devices
        let nextPairingCandidates = snapshot.pairingCandidates
        let nextWirelessCandidates = snapshot.wirelessConnectionCandidates
        let nextVisibleWirelessCandidates = visibleWirelessCandidates(
            devices: nextDevices,
            candidates: nextWirelessCandidates
        )
        let nextClassifiedEndpoints = nextDevices.map {
            endpointClassifier.endpoint(
                for: $0,
                wirelessCandidates: nextWirelessCandidates
            )
        }
        var nextDeviceDirectory = deviceDirectory
        let nextDirectoryPresentation = nextDeviceDirectory.observe(
            endpoints: nextClassifiedEndpoints
        )
        let nextVisibleEndpoints = nextDirectoryPresentation.connected.flatMap(\.endpoints)
        let updateWasAccepted = connectionCoordinator.send(
            .discoveryCompleted(
                token: token,
                endpoints: nextVisibleEndpoints,
                nearbySecureEndpointCount: nextVisibleWirelessCandidates.count,
                pairingAvailable: !nextPairingCandidates.isEmpty
            )
        )
        guard updateWasAccepted else { return }

        let wasFailing = discoveryMessage != nil
        devices = nextDevices
        pairingCandidates = nextPairingCandidates
        wirelessConnectionCandidates = nextWirelessCandidates
        deviceDirectory = nextDeviceDirectory
        deviceDirectoryPresentation = nextDirectoryPresentation
        persistDeviceDirectory()
        if let warning = snapshot.wirelessDiscoveryWarning {
            var message = "USB connections are still available, but nearby Wi-Fi discovery failed: \(warning)"
            if possibleLegacySourceUSBSerial != nil {
                message += " A previous USB-assisted setup may also have left an unencrypted listener active; reconnect the original phone over USB and use Turn Off."
            }
            connectionCoordinator.send(
                .noticeUpdated(
                    ConnectionNotice(
                        scope: .wirelessDiscovery,
                        kind: .warning,
                        message: message,
                        recovery: .refresh
                    )
                )
            )
        } else if possibleLegacySourceUSBSerial != nil {
            connectionCoordinator.send(
                .noticeUpdated(
                    ConnectionNotice(
                        scope: .wirelessDiscovery,
                        kind: .warning,
                        message: "A previous USB-assisted setup may have left an unencrypted listener active. Reconnect the original phone over USB and use Turn Off before treating that risk as cleared.",
                        recovery: .refresh
                    )
                )
            )
        } else {
            connectionCoordinator.send(.noticeCleared(.wirelessDiscovery))
        }
        discoveryMessage = nil

        let authorizedCount = devices.filter { $0.state == .authorized }.count
        let telemetrySummary = DiscoveryTelemetrySummary(
            authorizedCount: authorizedCount,
            deviceCount: devices.count,
            pairingCandidateCount: pairingCandidates.count,
            wirelessCandidateCount: wirelessConnectionCandidates.count
        )
        if wasFailing || telemetrySummary != lastDiscoveryTelemetrySummary {
            logger.info("device discovery changed authorized=\(authorizedCount, privacy: .public) total=\(self.devices.count, privacy: .public) pairingCandidates=\(self.pairingCandidates.count, privacy: .public) wirelessCandidates=\(self.wirelessConnectionCandidates.count, privacy: .public)")
            lastDiscoveryTelemetrySummary = telemetrySummary
        }

        if let sidebarSelection, !selectionStillExists(sidebarSelection) {
            self.sidebarSelection = nil
        }
        if sidebarSelection == nil {
            if let device = devices.first(where: { $0.state == .authorized }) {
                sidebarSelection = .device(device.id)
            } else if let candidate = visibleWirelessConnectionCandidates.first {
                sidebarSelection = .wirelessCandidate(candidate.id)
            }
        }
        if let navigationSelection,
           !navigationSelectionStillExists(navigationSelection) {
            self.navigationSelection = nil
        }
        if navigationSelection == nil {
            if requiresUSBDisambiguation {
                navigationSelection = .usbAutomatic
            } else if let item = connectedDeviceItems.first {
                navigationSelection = .device(item.id)
                activateNavigationSelection()
            } else {
                navigationSelection = .usbAutomatic
            }
        }

        if let pendingLegacyVerification,
           !connectionCoordinator.isCurrent(pendingLegacyVerification.operationToken) {
            self.pendingLegacyVerification = nil
        } else if let pendingLegacyVerification {
            if let connectedDevice = devices.first(where: {
                $0.identity.serial == pendingLegacyVerification.wirelessSerial
                    && $0.state == .authorized
            }) {
                recordLegacyProvenance(
                    sourceUSBSerial: pendingLegacyVerification.sourceUSB.serial,
                    wirelessSerial: connectedDevice.identity.serial
                )
                connectionCoordinator.send(
                    .legacySetupCompleted(
                        sourceUSBSerial: pendingLegacyVerification.sourceUSB.serial,
                        wirelessIdentity: DeviceIdentity(
                            serial: connectedDevice.identity.serial,
                            displayName: pendingLegacyVerification.sourceUSB.displayName
                        )
                    )
                )
                updateDeviceDirectoryFromCurrentObservation()
                sidebarSelection = .device(connectedDevice.id)
                navigationSelection = .device(
                    .usb(serial: pendingLegacyVerification.sourceUSB.serial)
                )
                wirelessConnectionMessage = "Connected over Wi-Fi. You can unplug USB now; repeat this setup after the phone restarts."
                connectionCoordinator.send(
                    .noticeUpdated(
                        ConnectionNotice(
                            scope: .wirelessSetup,
                            kind: .success,
                            message: "The exact Wi-Fi endpoint is authorized. You can unplug USB now."
                        )
                    )
                )
                self.pendingLegacyVerification = nil
                logger.info("USB-bootstrapped TCP/IP connection completed and exact endpoint selected")
            } else {
                wirelessConnectionMessage = "Wi-Fi is enabled, but the exact wireless endpoint is not authorized yet. Keep USB attached while TetherPane retries verification."
            }
        }

        if let pendingSecureVerification,
           !connectionCoordinator.isCurrent(pendingSecureVerification.operationToken) {
            self.pendingSecureVerification = nil
        } else if let pendingSecureVerification {
            if let connectedDevice = devices.first(where: {
                $0.identity.serial == pendingSecureVerification.wirelessSerial
                    && $0.state == .authorized
            }) {
                endpointClassifier.recordSecureService(
                    pendingSecureVerification.serviceName,
                    for: connectedDevice.identity.serial
                )
                let recordID = DeviceRecordID.secureService(
                    name: pendingSecureVerification.serviceName
                )
                deviceDirectory.markConnected(recordID)
                updateDeviceDirectoryFromCurrentObservation()
                sidebarSelection = .device(connectedDevice.id)
                navigationSelection = .device(recordID)
                connectionCoordinator.send(
                    .endpointSelected(serial: connectedDevice.identity.serial)
                )
                wirelessConnectionMessage = "Connected securely over Wi-Fi. No USB cable is required."
                connectionCoordinator.send(
                    .noticeUpdated(
                        ConnectionNotice(
                            scope: .wirelessSetup,
                            kind: .success,
                            message: "Secure Wireless Debugging is authorized and ready."
                        )
                    )
                )
                self.pendingSecureVerification = nil
                logger.info("wireless connection completed and exact endpoint selected")
            } else {
                wirelessConnectionMessage = "ADB accepted the secure connection, but the exact authorized endpoint is not visible yet. Keep Wireless Debugging open while TetherPane retries."
            }
        }

        if let pendingPairingVerification,
           !connectionCoordinator.isCurrent(pendingPairingVerification.operationToken) {
            self.pendingPairingVerification = nil
        } else if let pendingPairingVerification,
           let connectionCandidate = snapshot.wirelessConnectionCandidate(
               matching: pendingPairingVerification.candidate
           ) {
            self.pendingPairingVerification = nil
            connectWirelessly(candidate: connectionCandidate)
        }
    }

    private func applyDiscoveryFailure(
        _ error: any Error,
        token: ConnectionOperationToken
    ) {
        let failureWasAccepted = connectionCoordinator.send(
            .discoveryFailed(token: token, message: error.localizedDescription)
        )
        guard failureWasAccepted else { return }

        let shouldLogFailure = discoveryMessage == nil
        devices = []
        pairingCandidates = []
        wirelessConnectionCandidates = []
        sidebarSelection = nil
        deviceDirectoryPresentation = deviceDirectory.observe(endpoints: [])
        persistDeviceDirectory()
        discoveryMessage = error.localizedDescription
        if shouldLogFailure {
            logger.error("device discovery failed")
        }
    }

    private func selectionStillExists(_ selection: DeviceSidebarSelection) -> Bool {
        switch selection {
        case let .device(id):
            devices.contains(where: { $0.id == id })
        case let .wirelessCandidate(id):
            visibleWirelessConnectionCandidates.contains(where: { $0.id == id })
        }
    }

    private func navigationSelectionStillExists(
        _ selection: ControlCenterNavigationSelection
    ) -> Bool {
        switch selection {
        case let .device(id):
            (connectedDeviceItems + offlineDeviceItems).contains(where: { $0.id == id })
        case .usbAutomatic, .wifiOnly:
            true
        }
    }

    private func preferredEndpoint(for item: DeviceListItem) -> ADBEndpoint? {
        item.endpoints
            .filter { $0.authorization == .authorized || $0.authorization == .unauthorized }
            .sorted { lhs, rhs in
                lhs.route.devicePresentationPriority
                    < rhs.route.devicePresentationPriority
            }
            .first
    }

    private func classifiedEndpoints() -> [ADBEndpoint] {
        devices.map {
            endpointClassifier.endpoint(
                for: $0,
                wirelessCandidates: wirelessConnectionCandidates
            )
        }
    }

    private func updateDeviceDirectoryFromCurrentObservation() {
        deviceDirectoryPresentation = deviceDirectory.observe(
            endpoints: classifiedEndpoints()
        )
        persistDeviceDirectory()
        connectionCoordinator.send(
            .discoveryUpdated(
                endpoints: deviceDirectoryPresentation.connected.flatMap(\.endpoints),
                nearbySecureEndpointCount: visibleWirelessConnectionCandidates.count,
                pairingAvailable: !pairingCandidates.isEmpty
            )
        )
    }

    private func persistDeviceDirectory() {
        deviceDirectoryStore.save(deviceDirectory.savedRecords)
    }

    private func recordLegacyProvenance(
        sourceUSBSerial: String,
        wirelessSerial: String
    ) {
        endpointClassifier.recordLegacyTransition(
            sourceUSBSerial: sourceUSBSerial,
            wirelessSerial: wirelessSerial
        )
    }

    private func recordPossibleLegacyRisk(sourceUSBSerial: String) {
        possibleLegacySourceUSBSerial = sourceUSBSerial
        legacyRiskStore.save(sourceUSBSerial: sourceUSBSerial)
    }

    private func finishLegacyDisablement(device: DiscoveredDevice) {
        if device.transport == .usb {
            connectionCoordinator.send(
                .legacySetupFailed(sourceUSBSerial: device.identity.serial)
            )
        }
        var wirelessSerials: [String] = []
        if device.transport == .wireless {
            wirelessSerials.append(device.identity.serial)
        }
        wirelessSerials.append(contentsOf:
            endpointClassifier.verifiedLegacySources.compactMap { wirelessSerial, sourceUSBSerial in
                sourceUSBSerial == device.identity.serial ? wirelessSerial : nil
            }
        )
        for wirelessSerial in Set(wirelessSerials) {
            endpointClassifier.removeLegacyTransition(for: wirelessSerial)
            connectionCoordinator.send(
                .legacyTurnedOff(wirelessSerial: wirelessSerial)
            )
        }
        possibleLegacySourceUSBSerial = nil
        legacyRiskStore.clear()
        updateDeviceDirectoryFromCurrentObservation()
    }

    private func visibleWirelessCandidates(
        devices: [DiscoveredDevice],
        candidates: [WirelessConnectionCandidate]
    ) -> [WirelessConnectionCandidate] {
        candidates.filter { candidate in
            !devices.contains(where: { device in
                guard device.transport == .wireless else { return false }
                return device.identity.serial == candidate.endpoint.adbAddress
                    || device.identity.serial
                        == "\(candidate.serviceName)._adb-tls-connect._tcp"
            })
        }
    }
}
