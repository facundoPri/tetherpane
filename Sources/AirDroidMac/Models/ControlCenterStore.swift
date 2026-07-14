import AirDroidDomain
import AirDroidScrcpy
import Foundation
import Observation
import OSLog

enum DeviceSidebarSelection: Hashable {
    case device(String)
    case wirelessCandidate(String)
}

@MainActor
@Observable
final class ControlCenterStore {
    private let discovery: any DeviceDiscovery
    private let pairing: any PairingClient
    private let wirelessConnection: any WirelessConnectionClient
    private let mirroring: any MirroringEngine
    private let logger = Logger(subsystem: "com.facundopri.airdroid.spike", category: "Connection")

    var devices: [DiscoveredDevice] = []
    var pairingCandidates: [PairingCandidate] = []
    var wirelessConnectionCandidates: [WirelessConnectionCandidate] = []
    var sidebarSelection: DeviceSidebarSelection?
    var selectedPreset: MirrorPreset = .responsive
    var audioEnabled = true
    var recordNextSession = false
    var isAdvancedVisible = false
    var discoveryMessage: String?
    var sessionMessage: String?
    var sessionState: MirroringSessionState = .idle
    var effectiveInvocation: ScrcpyInvocation?
    var pairingMessage: String?
    var wirelessConnectionMessage: String?
    var qrPairingSession: WirelessQRCodePairingSession?
    private var qrPairingTarget: WirelessConnectionCandidate?
    private var pendingPairingCandidate: PairingCandidate?
    let resolvedADBPath: String
    let resolvedScrcpyPath: String

    init(
        discovery: any DeviceDiscovery,
        pairing: any PairingClient,
        wirelessConnection: any WirelessConnectionClient,
        mirroring: any MirroringEngine,
        resolvedADBPath: String? = DeveloperToolPathResolver.adbPath(),
        resolvedScrcpyPath: String? = DeveloperToolPathResolver.scrcpyPath()
    ) {
        self.discovery = discovery
        self.pairing = pairing
        self.wirelessConnection = wirelessConnection
        self.mirroring = mirroring
        self.resolvedADBPath = resolvedADBPath ?? "Unavailable"
        self.resolvedScrcpyPath = resolvedScrcpyPath ?? "Unavailable"
        self.mirroring.stateDidChange = { [weak self] state in
            self?.sessionState = state
            if case let .failed(message) = state {
                self?.sessionMessage = message
            }
        }
    }

    func refreshDevices() {
        logger.info("device discovery requested")
        do {
            let snapshot = try discovery.discover()
            devices = snapshot.devices
            pairingCandidates = snapshot.pairingCandidates
            wirelessConnectionCandidates = snapshot.wirelessConnectionCandidates
            discoveryMessage = nil
            let authorizedCount = devices.filter { $0.state == .authorized }.count
            logger.info("device discovery completed authorized=\(authorizedCount, privacy: .public) total=\(self.devices.count, privacy: .public) pairingCandidates=\(self.pairingCandidates.count, privacy: .public) wirelessCandidates=\(self.wirelessConnectionCandidates.count, privacy: .public)")

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

            if let pendingPairingCandidate,
               let connectionCandidate = snapshot.wirelessConnectionCandidate(
                   matching: pendingPairingCandidate
               ) {
                self.pendingPairingCandidate = nil
                connectWirelessly(candidate: connectionCandidate)
            }
        } catch {
            devices = []
            pairingCandidates = []
            wirelessConnectionCandidates = []
            sidebarSelection = nil
            discoveryMessage = error.localizedDescription
            logger.error("device discovery failed")
        }
    }

    var isMirroring: Bool {
        if case .mirroring = sessionState {
            true
        } else {
            false
        }
    }

    var selectedDevice: DiscoveredDevice? {
        guard case let .device(id) = sidebarSelection else {
            return nil
        }
        return devices.first(where: { $0.id == id })
    }

    var selectedWirelessCandidate: WirelessConnectionCandidate? {
        guard case let .wirelessCandidate(id) = sidebarSelection else {
            return nil
        }
        return visibleWirelessConnectionCandidates.first(where: { $0.id == id })
    }

    var visibleWirelessConnectionCandidates: [WirelessConnectionCandidate] {
        wirelessConnectionCandidates.filter { candidate in
            !devices.contains(where: { device in
                guard device.transport == .wireless else { return false }
                let endpoint = candidate.host.contains(":")
                    ? "[\(candidate.host)]:\(candidate.port)"
                    : "\(candidate.host):\(candidate.port)"
                return device.identity.serial == endpoint
                    || device.identity.serial.contains(candidate.serviceName)
            })
        }
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
        if isMirroring {
            stopMirroring()
            return
        }

        guard let selectedDevice, selectedDevice.state == .authorized else {
            sessionMessage = "Select an authorized Android device before mirroring."
            return
        }

        let recordingURL: URL?
        if recordNextSession {
            do {
                recordingURL = try RecordingDestination.nextURL()
            } catch {
                recordingURL = nil
                recordNextSession = false
                sessionMessage = "Recording could not be prepared, so this session will start without recording."
            }
        } else {
            recordingURL = nil
        }

        let configuration = MirroringConfiguration(
            device: selectedDevice.identity,
            preset: selectedPreset,
            audioEnabled: audioEnabled,
            recordingURL: recordingURL
        )

        do {
            effectiveInvocation = try mirroring.start(configuration: configuration)
            sessionState = mirroring.state
            if recordingURL != nil {
                sessionMessage = "Recording will be written when this scrcpy session stops."
            } else if sessionMessage == nil {
                sessionMessage = nil
            }
        } catch {
            sessionState = mirroring.state
            sessionMessage = error.localizedDescription
        }
    }

    func stopMirroring() {
        mirroring.stop()
        sessionState = mirroring.state
        sessionMessage = "Mirroring stopped."
    }

    func reconnect() {
        stopMirroring()
        toggleMirroring()
    }

    func pair(candidate: PairingCandidate, code: String) {
        logger.info("wireless pairing requested")
        do {
            try pairing.pair(candidate: candidate, code: code)
            pairingMessage = "Paired successfully. Waiting for this phone's Wi-Fi connection service."
            logger.info("wireless pairing completed")
            finishPairing(candidate: candidate)
        } catch {
            pairingMessage = error.localizedDescription
            logger.error("wireless pairing failed")
        }
    }

    func connectWirelessly(candidate: WirelessConnectionCandidate) {
        logger.info("wireless connection requested")
        do {
            let connection = try wirelessConnection.connect(candidate: candidate)
            refreshDevices()

            if let connectedDevice = devices.first(where: {
                $0.identity.serial == connection.deviceSerial && $0.state == .authorized
            }) {
                sidebarSelection = .device(connectedDevice.id)
                wirelessConnectionMessage = "Connected over Wi-Fi. This device is selected; a USB cable is not required."
                logger.info("wireless connection completed and exact device selected")
            } else {
                wirelessConnectionMessage = "ADB accepted the Wi-Fi connection, but the exact device is not visible yet. Keep Wireless Debugging on and refresh devices once more."
                logger.error("wireless connection completed without a discoverable exact device")
            }
        } catch {
            wirelessConnectionMessage = error.localizedDescription
            logger.error("wireless connection failed")
        }
    }

    func beginQRCodePairing(for candidate: WirelessConnectionCandidate) {
        qrPairingTarget = candidate
        qrPairingSession = WirelessQRCodePairingSessionFactory.make()
        pairingMessage = "Waiting for the phone to scan the QR code."
        logger.info("wireless QR pairing session started")
    }

    func cancelQRCodePairing() {
        qrPairingSession = nil
        qrPairingTarget = nil
        pairingMessage = "QR pairing canceled."
        logger.info("wireless QR pairing session canceled")
    }

    func continueQRCodePairing() {
        guard let session = qrPairingSession,
              let target = qrPairingTarget
        else {
            return
        }

        refreshDevices()
        guard let candidate = pairingCandidates.first(where: {
            $0.serviceName == session.serviceName && $0.host == target.host
        }) else {
            return
        }

        logger.info("wireless QR pairing service discovered")
        do {
            try pairing.pair(candidate: candidate, code: session.password)
            qrPairingSession = nil
            qrPairingTarget = nil
            pairingMessage = "QR pairing succeeded. Connecting over Wi-Fi."
            logger.info("wireless QR pairing completed")
            finishPairing(candidate: candidate)
        } catch {
            qrPairingSession = nil
            qrPairingTarget = nil
            pairingMessage = error.localizedDescription
            logger.error("wireless QR pairing failed")
        }
    }

    private func finishPairing(candidate: PairingCandidate) {
        pendingPairingCandidate = candidate
        refreshDevices()
        if pendingPairingCandidate != nil {
            wirelessConnectionMessage = "Pairing succeeded. Waiting for this phone's Wi-Fi connection service; no cable is required."
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
}
