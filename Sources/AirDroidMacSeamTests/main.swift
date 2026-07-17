import AirDroidDomain
import AirDroidScrcpy
import Foundation
import TetherPaneUIFixtureSupport

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fputs("FAIL: \(message)\nExpected: \(expected)\nActual: \(actual)\n", stderr)
        exit(1)
    }
}

private func expectThrows(_ message: String, operation: () throws -> Void) {
    do {
        try operation()
        fputs("FAIL: \(message)\nExpected an error, but the operation succeeded.\n", stderr)
        exit(1)
    } catch {
        return
    }
}

private func expectErrorDescription(
    _ expected: String,
    _ message: String,
    operation: () throws -> Void
) {
    do {
        try operation()
        fputs("FAIL: \(message)\nExpected an error, but the operation succeeded.\n", stderr)
        exit(1)
    } catch {
        expectEqual(error.localizedDescription, expected, message)
    }
}

let configuration = MirroringConfiguration(
    device: DeviceIdentity(serial: "motorola-usb-serial", displayName: "Motorola edge 40 pro"),
    preset: .responsive,
    audioEnabled: true,
    recordingURL: URL(filePath: "/tmp/motorola-session.mp4")
)

let invocation = ScrcpyCommandBuilder().build(configuration: configuration)
expectEqual(
    invocation.arguments,
    [
        "--serial=motorola-usb-serial",
        "--video-codec=h264",
        "--max-size=1280",
        "--max-fps=60",
        "--video-bit-rate=8M",
        "--record=/tmp/motorola-session.mp4",
        "--window-title=Motorola edge 40 pro",
    ],
    "Responsive preset must target exactly the selected device with known-good scrcpy 4.1 arguments"
)

print("PASS: Responsive preset targets the selected device with known-good scrcpy 4.1 arguments")

let highQualityInvocation = ScrcpyCommandBuilder().build(
    configuration: MirroringConfiguration(
        device: DeviceIdentity(serial: "wifi-exact-serial", displayName: "Wi-Fi device"),
        preset: .highQuality,
        audioEnabled: false,
        recordingURL: nil
    )
)
expectEqual(
    highQualityInvocation.arguments,
    [
        "--serial=wifi-exact-serial",
        "--video-codec=h265",
        "--max-size=1920",
        "--max-fps=60",
        "--video-bit-rate=16M",
        "--no-audio",
        "--window-title=Wi-Fi device",
    ],
    "High Quality must use the selected Wi-Fi serial, H.265 settings, and explicit audio opt-out"
)

print("PASS: High Quality preset maps audio-off to known-good scrcpy 4.1 arguments")

struct FixtureCommandRunner: CommandRunning {
    let results: [String: CommandResult]

    func run(executable: String, arguments: [String]) throws -> CommandResult {
        let key = arguments.joined(separator: " ")
        guard let result = results[key] else {
            fatalError("Missing command fixture for \(executable) \(key)")
        }
        return result
    }
}

let fixtureRunner = FixtureCommandRunner(results: [
    "devices -l": CommandResult(
        stdout: """
        List of devices attached
        usb-serial device usb:1-2 product:rtwo_g model:motorola_edge_40_pro device:rtwo
        192.168.1.44:40631 device product:rtwo_g model:motorola_edge_40_pro device:rtwo transport_id:4
        adb-connected-123._adb-tls-connect._tcp device product:rtwo_g model:motorola_edge_40_pro device:rtwo transport_id:5
        offline-serial offline transport_id:3
        waiting-serial unauthorized usb:1-3
        """,
        stderr: "",
        exitStatus: 0
    ),
    "mdns services": CommandResult(
        stdout: """
        List of discovered mdns services
        adb-pairing-123 _adb-tls-pairing._tcp 192.168.1.44:37001
        adb-connected-123 _adb-tls-connect._tcp 192.168.1.44:40631
        """,
        stderr: "",
        exitStatus: 0
    ),
])

let discovery = ADBDeviceDiscovery(adbPath: "/usr/local/bin/adb", runner: fixtureRunner)
let snapshot = try discovery.discover()
expectEqual(
    snapshot.devices.map(\.state),
    [.authorized, .authorized, .offline, .unauthorized],
    "Device discovery must normalize ADB authorization states"
)
expectEqual(
    snapshot.devices.map(\.transport),
    [.usb, .wireless, .unknown, .usb],
    "Device discovery must distinguish USB and wireless transports for exact-device selection"
)
expectEqual(
    snapshot.devices.first?.identity,
    DeviceIdentity(serial: "usb-serial", displayName: "motorola edge 40 pro"),
    "Device discovery must retain the exact serial and a normalized display name"
)
expectEqual(
    snapshot.pairingCandidates,
    [PairingCandidate(serviceName: "adb-pairing-123", host: "192.168.1.44", port: 37001)],
    "Device discovery must expose only mDNS pairing candidates, not regular ADB connection services"
)
expectEqual(
    snapshot.wirelessConnectionCandidates,
    [WirelessConnectionCandidate(serviceName: "adb-connected-123", host: "192.168.1.44", port: 40631)],
    "Device discovery must expose mDNS wireless connection candidates separately from pairing services"
)
expectEqual(
    snapshot.wirelessConnectionCandidate(matching: snapshot.pairingCandidates[0]),
    WirelessConnectionCandidate(
        serviceName: "adb-connected-123",
        host: "192.168.1.44",
        port: 40631
    ),
    "A pairing endpoint must resolve only to the same phone's Wi-Fi connection service"
)

print("PASS: ADB discovery normalizes devices, pairing services, and wireless connection services")

let silentFailureDiscovery = ADBDeviceDiscovery(
    adbPath: "/usr/bin/false",
    runner: FixtureCommandRunner(results: [
        "devices -l": CommandResult(stdout: "", stderr: "", exitStatus: 1),
    ])
)
expectErrorDescription(
    "ADB devices -l failed: command exited with status 1 without output.",
    "A silent ADB failure must still produce an actionable command error"
) {
    _ = try silentFailureDiscovery.discover()
}

print("PASS: ADB discovery explains silent command failures")

final class RecordingCommandRunner: StandardInputCommandRunning, @unchecked Sendable {
    private(set) var launches: [(executable: String, arguments: [String])] = []
    private(set) var standardInputs: [String] = []
    let result: CommandResult

    init(result: CommandResult) {
        self.result = result
    }

    func run(executable: String, arguments: [String]) throws -> CommandResult {
        launches.append((executable, arguments))
        return result
    }

    func run(
        executable: String,
        arguments: [String],
        standardInput: String
    ) throws -> CommandResult {
        launches.append((executable, arguments))
        standardInputs.append(standardInput)
        return result
    }
}

let pairingRunner = RecordingCommandRunner(
    result: CommandResult(stdout: "Successfully paired", stderr: "", exitStatus: 0)
)
let pairingClient = ADBPairingClient(adbPath: "/usr/local/bin/adb", runner: pairingRunner)
try pairingClient.pair(
    candidate: PairingCandidate(serviceName: "adb-pairing-123", host: "192.168.1.44", port: 37001),
    code: "123456"
)
expectEqual(
    pairingRunner.launches.first?.arguments,
    ["pair", "192.168.1.44:37001"],
    "Pairing must not expose the supplied short-lived code in the process argument list"
)
expectEqual(
    pairingRunner.standardInputs,
    ["123456\n"],
    "Pairing must supply the short-lived code to ADB through standard input"
)

print("PASS: ADB pairing sends the discovered endpoint and does not retain the one-shot code")

let rejectedPairingRunner = RecordingCommandRunner(
    result: CommandResult(
        stdout: "Failed: Unable to start pairing client.",
        stderr: "",
        exitStatus: 0
    )
)
let rejectedPairingClient = ADBPairingClient(
    adbPath: "/usr/local/bin/adb",
    runner: rejectedPairingRunner
)
expectThrows("Pairing must reject ADB's textual failure even when the process exits successfully") {
    try rejectedPairingClient.pair(
        candidate: PairingCandidate(
            serviceName: "adb-pairing-123",
            host: "192.168.1.44",
            port: 37001
        ),
        code: "123456"
    )
}

print("PASS: ADB pairing rejects textual failures from stock adb")

let wirelessConnectionRunner = RecordingCommandRunner(
    result: CommandResult(stdout: "connected to 192.168.1.44:40631", stderr: "", exitStatus: 0)
)
let wirelessConnectionClient = ADBWirelessConnectionClient(
    adbPath: "/usr/local/bin/adb",
    runner: wirelessConnectionRunner
)
let wirelessConnection = try wirelessConnectionClient.connect(
    candidate: WirelessConnectionCandidate(
        serviceName: "adb-connected-123",
        host: "192.168.1.44",
        port: 40631
    )
)
expectEqual(
    wirelessConnectionRunner.launches.first?.arguments,
    ["connect", "192.168.1.44:40631"],
    "Wireless connection must invoke ADB for exactly the mDNS-discovered endpoint"
)
expectEqual(
    wirelessConnection.deviceSerial,
    "192.168.1.44:40631",
    "Wireless connection must return the exact ADB serial that scrcpy should target"
)

print("PASS: ADB wireless connection targets the discovered endpoint and returns its exact device serial")

final class OrderedCommandRunner: CommandRunning, @unchecked Sendable {
    struct Step {
        let arguments: [String]
        let result: CommandResult
    }

    private var remainingSteps: [Step]
    private(set) var launches: [(executable: String, arguments: [String])] = []

    init(steps: [Step]) {
        remainingSteps = steps
    }

    func run(executable: String, arguments: [String]) throws -> CommandResult {
        guard !remainingSteps.isEmpty else {
            fatalError("Unexpected command: \(executable) \(arguments.joined(separator: " "))")
        }
        let step = remainingSteps.removeFirst()
        expectEqual(arguments, step.arguments, "ADB TCP/IP setup must execute the expected command sequence")
        launches.append((executable, arguments))
        return step.result
    }
}

let legacyWirelessRunner = OrderedCommandRunner(steps: [
    .init(
        arguments: ["-s", "usb-exact-serial", "shell", "ip", "-f", "inet", "addr", "show", "wlan0"],
        result: CommandResult(
            stdout: "6: wlan0: <UP> mtu 1500\n    inet 192.168.1.44/24 brd 192.168.1.255 scope global wlan0\n",
            stderr: "",
            exitStatus: 0
        )
    ),
    .init(
        arguments: ["-s", "usb-exact-serial", "tcpip", "5555"],
        result: CommandResult(
            stdout: "restarting in TCP mode port: 5555\n",
            stderr: "",
            exitStatus: 0
        )
    ),
    .init(
        arguments: ["connect", "192.168.1.44:5555"],
        result: CommandResult(
            stdout: "connected to 192.168.1.44:5555\n",
            stderr: "",
            exitStatus: 0
        )
    ),
])
let legacyWirelessClient = ADBWirelessConnectionClient(
    adbPath: "/usr/local/bin/adb",
    runner: legacyWirelessRunner
)
let legacyWirelessConnection = try legacyWirelessClient.connectOverTCPIP(
    device: DeviceIdentity(serial: "usb-exact-serial", displayName: "Motorola edge 40 pro")
)
expectEqual(
    legacyWirelessConnection.deviceSerial,
    "192.168.1.44:5555",
    "USB-bootstrapped TCP/IP setup must return the exact Wi-Fi serial that scrcpy should target"
)

print("PASS: ADB TCP/IP setup discovers the selected USB device Wi-Fi address and connects its exact serial")

let nonstandardWifiInterfaceRunner = OrderedCommandRunner(steps: [
    .init(
        arguments: ["-s", "motorola-usb-serial", "shell", "ip", "-f", "inet", "addr", "show", "wlan0"],
        result: CommandResult(stdout: "", stderr: "", exitStatus: 0)
    ),
    .init(
        arguments: ["-s", "motorola-usb-serial", "shell", "ip", "-4", "route"],
        result: CommandResult(
            stdout: "192.168.1.0/24 dev wlan1 proto kernel scope link src 192.168.1.3\n",
            stderr: "",
            exitStatus: 0
        )
    ),
    .init(
        arguments: ["-s", "motorola-usb-serial", "tcpip", "5555"],
        result: CommandResult(stdout: "restarting in TCP mode port: 5555\n", stderr: "", exitStatus: 0)
    ),
    .init(
        arguments: ["connect", "192.168.1.3:5555"],
        result: CommandResult(stdout: "connected to 192.168.1.3:5555\n", stderr: "", exitStatus: 0)
    ),
])
let nonstandardWifiInterfaceClient = ADBWirelessConnectionClient(
    adbPath: "/usr/local/bin/adb",
    runner: nonstandardWifiInterfaceRunner
)
let nonstandardWifiConnection = try nonstandardWifiInterfaceClient.connectOverTCPIP(
    device: DeviceIdentity(serial: "motorola-usb-serial", displayName: "Motorola edge 40 pro")
)
expectEqual(
    nonstandardWifiConnection.deviceSerial,
    "192.168.1.3:5555",
    "TCP/IP setup must fall back to the active IPv4 route when an OEM uses a Wi-Fi interface other than wlan0"
)

print("PASS: ADB TCP/IP setup supports OEM Wi-Fi interfaces discovered through the active IPv4 route")

let developerOptionsRunner = RecordingCommandRunner(
    result: CommandResult(stdout: "Starting: Intent", stderr: "", exitStatus: 0)
)
let developerOptionsClient = ADBWirelessConnectionClient(
    adbPath: "/usr/local/bin/adb",
    runner: developerOptionsRunner
)
try developerOptionsClient.openDeveloperOptions(
    device: DeviceIdentity(serial: "usb-exact-serial", displayName: "Motorola edge 40 pro")
)
expectEqual(
    developerOptionsRunner.launches.first?.arguments,
    ["-s", "usb-exact-serial", "shell", "am", "start", "-a", "android.settings.APPLICATION_DEVELOPMENT_SETTINGS"],
    "The guided setup action must open Android Developer Options only on the selected USB device"
)

print("PASS: Guided setup opens Developer Options on the exact selected USB device without toggling settings")

let disableTCPIPRunner = RecordingCommandRunner(
    result: CommandResult(stdout: "restarting in USB mode\n", stderr: "", exitStatus: 0)
)
let disableTCPIPClient = ADBWirelessConnectionClient(
    adbPath: "/usr/local/bin/adb",
    runner: disableTCPIPRunner
)
try disableTCPIPClient.disableTCPIP(
    endpoint: ADBEndpoint(
        identity: DeviceIdentity(serial: "192.168.1.44:5555", displayName: "Motorola edge 40 pro"),
        authorization: .authorized,
        route: .legacyWirelessUntilRestart,
        provenance: .appInitiatedLegacyTransition(
            sourceUSBSerial: "usb-source",
            wirelessSerial: "192.168.1.44:5555"
        )
    )
)
expectEqual(
    disableTCPIPRunner.launches.map(\.arguments),
    [
        ["-s", "192.168.1.44:5555", "usb"],
        ["disconnect", "192.168.1.44:5555"],
    ],
    "Turning off USB-assisted Wi-Fi must close the selected phone's legacy listener and remove the stale host transport"
)

print("PASS: USB-assisted Wi-Fi can be turned off on the exact legacy TCP/IP device")

let protectiveUSBRunner = RecordingCommandRunner(
    result: CommandResult(stdout: "restarting in USB mode\n", stderr: "", exitStatus: 0)
)
let protectiveUSBClient = ADBWirelessConnectionClient(
    adbPath: "/usr/local/bin/adb",
    runner: protectiveUSBRunner
)
try protectiveUSBClient.disableTCPIP(
    endpoint: ADBEndpoint(
        identity: DeviceIdentity(serial: "usb-source", displayName: "Android phone"),
        authorization: .authorized,
        route: .directUSB,
        provenance: .adbUSBObservation
    )
)
expectEqual(
    protectiveUSBRunner.launches.map(\.arguments),
    [["-s", "usb-source", "usb"]],
    "A conservative post-interruption shutdown must target only the exact USB source and never disconnect a guessed IP endpoint"
)

print("PASS: Possible legacy risk can be cleared safely through the exact USB source")

final class FixtureRunningProcess: RunningProcess, @unchecked Sendable {
    private(set) var isRunning = true
    private(set) var terminateWasRequested = false
    private var terminationHandler: (@Sendable (Int32) -> Void)?

    func terminate() {
        terminateWasRequested = true
        isRunning = false
        terminationHandler?(0)
    }

    func observeTermination(_ handler: @escaping @Sendable (Int32) -> Void) {
        terminationHandler = handler
    }
}

final class FixtureProcessLauncher: ProcessLaunching, @unchecked Sendable {
    let process = FixtureRunningProcess()
    private(set) var launches: [(executable: String, arguments: [String])] = []
    private(set) var launchWasOnMainThread: Bool?
    private var outputHandler: (@Sendable (ScrcpyProcessOutput) -> Void)?

    func launch(
        executable: String,
        arguments: [String],
        outputHandler: @escaping @Sendable (ScrcpyProcessOutput) -> Void
    ) throws -> any RunningProcess {
        launchWasOnMainThread = Thread.isMainThread
        launches.append((executable, arguments))
        self.outputHandler = outputHandler
        return process
    }

    func emit(channel: ScrcpyOutputChannel, text: String) {
        outputHandler?(ScrcpyProcessOutput(channel: channel, text: text))
    }
}

let processLauncher = FixtureProcessLauncher()
let mirroringEngine = ScrcpyMirroringEngine(
    scrcpyPath: "/usr/local/bin/scrcpy",
    launcher: processLauncher,
    diagnosticLineLimit: 3
)
var lifecycleTransitions: [MirroringSessionState] = []
mirroringEngine.stateDidChange = { lifecycleTransitions.append($0) }
let highQualityConfiguration = MirroringConfiguration(
    device: DeviceIdentity(serial: "exact-serial", displayName: "Exact device"),
    preset: .highQuality,
    audioEnabled: false,
    recordingURL: URL(filePath: "/tmp/exact-device.mp4")
)

let launchedInvocation = try await mirroringEngine.start(configuration: highQualityConfiguration)
expectEqual(
    processLauncher.launchWasOnMainThread,
    false,
    "Mirroring process launch must run outside the main actor"
)
expectEqual(
    processLauncher.launches.first?.arguments,
    launchedInvocation.arguments,
    "Mirroring must launch the exact typed scrcpy invocation"
)
expectEqual(
    mirroringEngine.state,
    .mirroring(DeviceIdentity(serial: "exact-serial", displayName: "Exact device")),
    "Mirroring engine must expose an active exact-device lifecycle state"
)
processLauncher.emit(channel: .standardOutput, text: "INFO: device connected\nINFO: renderer ready\n")
processLauncher.emit(channel: .standardError, text: "WARN: audio fallback\nERROR: final diagnostic\n")
try await Task.sleep(for: .milliseconds(100))
expectEqual(
    mirroringEngine.diagnostics.recentLines,
    [
        ScrcpyDiagnosticLine(channel: .standardOutput, message: "INFO: renderer ready"),
        ScrcpyDiagnosticLine(channel: .standardError, message: "WARN: audio fallback"),
        ScrcpyDiagnosticLine(channel: .standardError, message: "ERROR: final diagnostic"),
    ],
    "Mirroring diagnostics must retain a bounded, ordered tail of scrcpy output"
)
await mirroringEngine.stop()
try await Task.sleep(for: .milliseconds(100))
expectEqual(processLauncher.process.terminateWasRequested, true, "Stopping must terminate the launched child process")
expectEqual(mirroringEngine.state, .stopped, "Stopping must expose a stopped lifecycle state")
expectEqual(mirroringEngine.diagnostics.lastExitStatus, 0, "Diagnostics must retain the expected child exit status")
_ = try await mirroringEngine.start(configuration: highQualityConfiguration)
expectEqual(processLauncher.launches.count, 2, "A stopped session must permit an exact-device reconnect")
expectEqual(lifecycleTransitions.contains(.stopped), true, "Lifecycle consumers must observe an explicit stopped state")
expectEqual(mirroringEngine.diagnostics.recentLines, [], "A reconnect must begin with a fresh diagnostic tail")

print("PASS: Mirroring engine launches, diagnoses, stops, and reconnects the exact typed scrcpy session")

final class UnexpectedExitProcess: RunningProcess, @unchecked Sendable {
    private(set) var isRunning = true
    private var terminationHandler: (@Sendable (Int32) -> Void)?

    func terminate() {
        finish(status: 0)
    }

    func observeTermination(_ handler: @escaping @Sendable (Int32) -> Void) {
        terminationHandler = handler
    }

    func finish(status: Int32) {
        isRunning = false
        terminationHandler?(status)
    }
}

final class UnexpectedExitLauncher: ProcessLaunching, @unchecked Sendable {
    let process = UnexpectedExitProcess()

    func launch(
        executable: String,
        arguments: [String],
        outputHandler: @escaping @Sendable (ScrcpyProcessOutput) -> Void
    ) throws -> any RunningProcess {
        process
    }
}

let unexpectedExitLauncher = UnexpectedExitLauncher()
let unexpectedExitEngine = ScrcpyMirroringEngine(
    scrcpyPath: "/usr/local/bin/scrcpy",
    launcher: unexpectedExitLauncher
)
var unexpectedExitTransition: MirroringSessionState?
unexpectedExitEngine.stateDidChange = { unexpectedExitTransition = $0 }
_ = try await unexpectedExitEngine.start(configuration: highQualityConfiguration)
unexpectedExitLauncher.process.finish(status: 70)
try await Task.sleep(for: .milliseconds(100))
expectEqual(
    unexpectedExitEngine.state,
    .failed("scrcpy stopped unexpectedly (exit 70). Reconnect to try again."),
    "An unexpected child exit must surface a reconnectable typed error state"
)
expectEqual(unexpectedExitTransition, unexpectedExitEngine.state, "Lifecycle consumers must observe an unexpected exit")
expectEqual(unexpectedExitEngine.diagnostics.lastExitStatus, 70, "Unexpected exit diagnostics must retain the exact status")

print("PASS: Mirroring engine surfaces an unexpected child-process exit")

var connectionCoordinator = ConnectionCoordinator()
expectEqual(
    connectionCoordinator.presentation.workspace,
    .disconnected,
    "A control center with no observed ADB endpoint must present the direct-USB-first disconnected workspace"
)

print("PASS: Connection presentation starts in the direct-USB-first disconnected state")

let unauthorizedUSBIdentity = DeviceIdentity(
    serial: "unauthorized-usb-exact",
    displayName: "Android phone"
)
connectionCoordinator.send(
    .discoveryUpdated(
        endpoints: [
            ADBEndpoint(
                identity: unauthorizedUSBIdentity,
                authorization: .unauthorized,
                route: .directUSB,
                provenance: .adbUSBObservation
            ),
        ],
        nearbySecureEndpointCount: 0,
        pairingAvailable: false
    )
)
expectEqual(
    connectionCoordinator.presentation.workspace,
    .usbAuthorizationRequired(unauthorizedUSBIdentity),
    "An unauthorized USB endpoint must ask the user to unlock the phone and approve Android's RSA dialog"
)

print("PASS: Connection presentation distinguishes USB authorization from disconnection")

let readyUSBEndpoint = ADBEndpoint(
    identity: DeviceIdentity(serial: "authorized-usb-exact", displayName: "Android phone"),
    authorization: .authorized,
    route: .directUSB,
    provenance: .adbUSBObservation
)
connectionCoordinator.send(
    .discoveryUpdated(
        endpoints: [readyUSBEndpoint],
        nearbySecureEndpointCount: 0,
        pairingAvailable: false
    )
)
expectEqual(
    connectionCoordinator.presentation.workspace,
    .ready(readyUSBEndpoint),
    "An authorized direct USB endpoint must become the one-device workspace's ready connection"
)

print("PASS: Connection presentation makes an authorized USB endpoint ready to mirror")

connectionCoordinator.send(.legacySetupStarted(sourceUSBSerial: readyUSBEndpoint.identity.serial))
expectEqual(
    connectionCoordinator.presentation.workspace,
    .legacyEnabling(readyUSBEndpoint),
    "Legacy Wi-Fi setup must keep the exact USB source visible and require the cable until verification completes"
)

print("PASS: Connection presentation keeps USB attached while legacy Wi-Fi is enabling")

let legacyWirelessIdentity = DeviceIdentity(
    serial: "192.0.2.44:5555",
    displayName: "Android phone"
)
connectionCoordinator.send(
    .legacySetupCompleted(
        sourceUSBSerial: readyUSBEndpoint.identity.serial,
        wirelessIdentity: legacyWirelessIdentity
    )
)
let verifiedLegacyEndpoint = ADBEndpoint(
    identity: legacyWirelessIdentity,
    authorization: .authorized,
    route: .legacyWirelessUntilRestart,
    provenance: .appInitiatedLegacyTransition(
        sourceUSBSerial: readyUSBEndpoint.identity.serial,
        wirelessSerial: legacyWirelessIdentity.serial
    )
)
expectEqual(
    connectionCoordinator.presentation.workspace,
    .legacySafeToUnplug(verifiedLegacyEndpoint),
    "Only an app-initiated USB-to-wireless transition may present legacy Wi-Fi as safe to unplug"
)

var restoredLegacyCoordinator = ConnectionCoordinator()
restoredLegacyCoordinator.send(
    .discoveryUpdated(
        endpoints: [verifiedLegacyEndpoint],
        nearbySecureEndpointCount: 0,
        pairingAvailable: false
    )
)
expectEqual(
    restoredLegacyCoordinator.presentation.workspace,
    .legacySafeToUnplug(verifiedLegacyEndpoint),
    "Explicit app-initiated provenance must restore active legacy risk disclosure without inferring from the IP serial"
)
restoredLegacyCoordinator.send(
    .legacyTurnedOff(wirelessSerial: verifiedLegacyEndpoint.identity.serial)
)
expectEqual(
    restoredLegacyCoordinator.presentation.workspace,
    .disconnected,
    "Turning off a restored legacy route must immediately remove its stale endpoint presentation"
)

print("PASS: Connection presentation records explicit legacy provenance before safe-to-unplug")

var secureWirelessCoordinator = ConnectionCoordinator()
secureWirelessCoordinator.send(
    .discoveryUpdated(
        endpoints: [],
        nearbySecureEndpointCount: 1,
        pairingAvailable: false
    )
)
expectEqual(
    secureWirelessCoordinator.presentation.workspace,
    .secureWirelessNearby(candidateCount: 1),
    "A nearby secure service must remain an unassociated candidate rather than an invented phone identity"
)

print("PASS: Connection presentation keeps nearby secure endpoints unassociated")

secureWirelessCoordinator.send(
    .discoveryUpdated(
        endpoints: [],
        nearbySecureEndpointCount: 1,
        pairingAvailable: true
    )
)
expectEqual(
    secureWirelessCoordinator.presentation.workspace,
    .securePairing(candidateCount: 1),
    "The temporary Android pairing service must promote the consolidated wireless flow to pairing"
)

print("PASS: Connection presentation distinguishes pairing from nearby discovery")

let secureWirelessEndpoint = ADBEndpoint(
    identity: DeviceIdentity(serial: "secure-wireless-exact", displayName: "Android phone"),
    authorization: .authorized,
    route: .secureWirelessDebugging,
    provenance: .secureServiceObservation(serviceName: "secure-service-id")
)
var secureReadyCoordinator = ConnectionCoordinator()
secureReadyCoordinator.send(
    .discoveryUpdated(
        endpoints: [secureWirelessEndpoint],
        nearbySecureEndpointCount: 0,
        pairingAvailable: false
    )
)
expectEqual(
    secureReadyCoordinator.presentation.workspace,
    .ready(secureWirelessEndpoint),
    "An authorized secure endpoint must be ready only with explicit secure-service provenance"
)

print("PASS: Connection presentation makes verified secure Wireless Debugging ready")

secureReadyCoordinator.send(
    .mirroringStarted(endpointSerial: secureWirelessEndpoint.identity.serial)
)
expectEqual(
    secureReadyCoordinator.presentation.workspace,
    .mirroring(secureWirelessEndpoint),
    "Mirroring presentation must retain the exact verified endpoint and its connection provenance"
)

print("PASS: Connection presentation retains the exact endpoint while mirroring")

let recordingPreparationWarning = ConnectionNotice(
    scope: .mirroring,
    kind: .warning,
    message: "Recording could not be prepared, so this session will start without recording."
)
secureReadyCoordinator.send(.noticeUpdated(recordingPreparationWarning))
expectEqual(
    secureReadyCoordinator.presentation.notice,
    recordingPreparationWarning,
    "A recording preparation failure must remain visible after exact-endpoint mirroring starts"
)

print("PASS: Connection presentation keeps recording fallback visible while mirroring")

var recoveryCoordinator = ConnectionCoordinator()
recoveryCoordinator.send(
    .operationFailed(
        scope: .discovery,
        message: "ADB temporarily unavailable",
        recovery: .refresh
    )
)
expectEqual(
    recoveryCoordinator.presentation.notice,
    ConnectionNotice(
        scope: .discovery,
        kind: .failure,
        message: "ADB temporarily unavailable",
        recovery: .refresh
    ),
    "A discovery failure must own typed, scoped recovery feedback"
)
recoveryCoordinator.send(
    .discoveryUpdated(
        endpoints: [readyUSBEndpoint],
        nearbySecureEndpointCount: 0,
        pairingAvailable: false
    )
)
expectEqual(
    recoveryCoordinator.presentation.workspace,
    .ready(readyUSBEndpoint),
    "Recovery must restore the current USB-ready workspace"
)
expectEqual(
    recoveryCoordinator.presentation.notice,
    nil,
    "A successful discovery must clear its stale failure instead of preserving an old message"
)

print("PASS: Connection presentation clears stale discovery feedback on scoped recovery")

let unclassifiedWirelessEndpoint = ADBEndpoint(
    identity: DeviceIdentity(serial: "192.0.2.55:5555", displayName: "Android phone"),
    authorization: .authorized,
    route: .unclassifiedWireless,
    provenance: .unverified
)
var unclassifiedCoordinator = ConnectionCoordinator()
unclassifiedCoordinator.send(
    .discoveryUpdated(
        endpoints: [unclassifiedWirelessEndpoint],
        nearbySecureEndpointCount: 0,
        pairingAvailable: false
    )
)
expectEqual(
    unclassifiedCoordinator.presentation.workspace,
    .ready(unclassifiedWirelessEndpoint),
    "An exact authorized endpoint may mirror without inferring legacy or secure provenance from its serial suffix"
)

print("PASS: Connection presentation never infers wireless provenance from a :5555 serial")

let classifierWirelessDevice = DiscoveredDevice(
    identity: DeviceIdentity(
        serial: "[2001:db8::44]:37123",
        displayName: "Android endpoint"
    ),
    state: .authorized,
    transport: .wireless
)
let classifierSecureCandidate = WirelessConnectionCandidate(
    serviceName: "secure-service",
    host: "2001:db8::44",
    port: 37123
)
var endpointClassifier = ConnectionEndpointClassifier(
    verifiedLegacySources: [classifierWirelessDevice.identity.serial: "usb-source"]
)
expectEqual(
    classifierSecureCandidate.endpoint.adbAddress,
    "[2001:db8::44]:37123",
    "Typed network endpoints must format IPv6 serials exactly as stock ADB expects"
)
expectEqual(
    endpointClassifier.endpoint(
        for: classifierWirelessDevice,
        wirelessCandidates: [classifierSecureCandidate]
    ).route,
    .secureWirelessDebugging,
    "A current exact secure service must override older in-memory legacy evidence for the same serial"
)
endpointClassifier.recordSecureService(
    "verified-secure-service",
    for: classifierWirelessDevice.identity.serial
)
expectEqual(
    endpointClassifier.endpoint(
        for: classifierWirelessDevice,
        wirelessCandidates: []
    ).provenance,
    .secureServiceObservation(serviceName: "verified-secure-service"),
    "Explicit secure-service evidence must remain associated with only its exact ADB endpoint"
)

print("PASS: Endpoint classifier keeps route provenance typed and secure evidence current")

var silentPollingCoordinator = ConnectionCoordinator()
let silentPollingToken = silentPollingCoordinator.beginOperation(
    scope: .discovery,
    message: "Refreshing connections…",
    showsProgress: false
)
expectEqual(
    silentPollingCoordinator.presentation.notice,
    nil,
    "Background discovery polling must keep its generation token without replacing user-facing feedback with repetitive progress"
)
expectEqual(
    silentPollingCoordinator.send(
        .discoveryCompleted(
            token: silentPollingToken,
            endpoints: [readyUSBEndpoint],
            nearbySecureEndpointCount: 0,
            pairingAvailable: false
        )
    ),
    true,
    "A silent discovery poll must still accept its current generation atomically"
)

print("PASS: Background discovery polling stays silent without weakening stale-result protection")

var wirelessGenerationCoordinator = ConnectionCoordinator()
let staleWirelessAction = wirelessGenerationCoordinator.beginOperation(
    scope: .wirelessSetup,
    message: "Connecting to the first endpoint…"
)
let currentWirelessAction = wirelessGenerationCoordinator.beginOperation(
    scope: .wirelessSetup,
    message: "Opening a newer wireless action…"
)
expectEqual(
    wirelessGenerationCoordinator.isCurrent(staleWirelessAction),
    false,
    "Starting a newer wireless action must invalidate verification from the older endpoint"
)
expectEqual(
    wirelessGenerationCoordinator.isCurrent(currentWirelessAction),
    true,
    "Only the latest wireless action generation may associate a discovered endpoint"
)

print("PASS: Wireless endpoint verification is scoped to the latest action generation")

var asynchronousCoordinator = ConnectionCoordinator()
let staleDiscovery = asynchronousCoordinator.beginOperation(
    scope: .discovery,
    message: "Refreshing connections…"
)
let currentDiscovery = asynchronousCoordinator.beginOperation(
    scope: .discovery,
    message: "Refreshing connections…"
)
let staleDiscoveryWasAccepted = asynchronousCoordinator.send(
    .discoveryCompleted(
        token: staleDiscovery,
        endpoints: [readyUSBEndpoint],
        nearbySecureEndpointCount: 0,
        pairingAvailable: false
    )
)
expectEqual(
    staleDiscoveryWasAccepted,
    false,
    "Callers must be able to reject stale discovery before mutating live store state"
)
expectEqual(
    asynchronousCoordinator.presentation.workspace,
    .disconnected,
    "A late completion from cancelled discovery work must not replace the current presentation"
)
let currentDiscoveryWasAccepted = asynchronousCoordinator.send(
    .discoveryCompleted(
        token: currentDiscovery,
        endpoints: [readyUSBEndpoint],
        nearbySecureEndpointCount: 0,
        pairingAvailable: false
    )
)
expectEqual(
    currentDiscoveryWasAccepted,
    true,
    "The current discovery generation must be accepted for one atomic store update"
)
expectEqual(
    asynchronousCoordinator.presentation.workspace,
    .ready(readyUSBEndpoint),
    "Only the current discovery generation may update the workspace"
)

print("PASS: Connection coordinator rejects stale asynchronous discovery results")

let partialDiscovery = ADBDeviceDiscovery(
    adbPath: "/usr/local/bin/adb",
    runner: FixtureCommandRunner(results: [
        "devices -l": CommandResult(
            stdout: """
            List of devices attached
            usb-still-ready device usb:1-2 model:Android_phone
            """,
            stderr: "",
            exitStatus: 0
        ),
        "mdns services": CommandResult(
            stdout: "",
            stderr: "mDNS unavailable",
            exitStatus: 1
        ),
    ])
)
let partialSnapshot = try partialDiscovery.discover()
expectEqual(
    partialSnapshot.devices.map(\.identity.serial),
    ["usb-still-ready"],
    "An mDNS failure must not remove a successfully discovered USB endpoint"
)
expectEqual(
    partialSnapshot.wirelessDiscoveryWarning,
    "ADB mdns services failed: mDNS unavailable",
    "Partial discovery must scope the failure to wireless discovery"
)

print("PASS: ADB discovery preserves USB results when mDNS fails")

var partialPresentationCoordinator = ConnectionCoordinator()
partialPresentationCoordinator.send(
    .discoveryUpdated(
        endpoints: [readyUSBEndpoint],
        nearbySecureEndpointCount: 0,
        pairingAvailable: false
    )
)
let wirelessOnlyWarning = ConnectionNotice(
    scope: .wirelessDiscovery,
    kind: .warning,
    message: "USB is ready, but nearby Wi-Fi discovery is temporarily unavailable.",
    recovery: .refresh
)
partialPresentationCoordinator.send(.noticeUpdated(wirelessOnlyWarning))
expectEqual(
    partialPresentationCoordinator.presentation.workspace,
    .ready(readyUSBEndpoint),
    "A wireless-only warning must preserve the working USB workspace"
)
expectEqual(
    partialPresentationCoordinator.presentation.notice,
    wirelessOnlyWarning,
    "A partial mDNS failure must be presented as a scoped warning"
)

print("PASS: Connection presentation scopes mDNS failure without removing USB readiness")

secureReadyCoordinator.send(.mirroringStopped)
expectEqual(
    secureReadyCoordinator.presentation.workspace,
    .ready(secureWirelessEndpoint),
    "Stopping a mirror must return to the same exact ready endpoint"
)

print("PASS: Connection presentation returns to the exact endpoint after mirroring stops")

let ambiguousAssociationSnapshot = DeviceDiscoverySnapshot(
    devices: [],
    pairingCandidates: [
        PairingCandidate(serviceName: "pairing", host: "192.0.2.90", port: 37000),
    ],
    wirelessConnectionCandidates: [
        WirelessConnectionCandidate(serviceName: "connect-a", host: "192.0.2.90", port: 37100),
        WirelessConnectionCandidate(serviceName: "connect-b", host: "192.0.2.90", port: 37200),
    ]
)
expectEqual(
    ambiguousAssociationSnapshot.wirelessConnectionCandidate(
        matching: ambiguousAssociationSnapshot.pairingCandidates[0]
    ),
    nil,
    "A pairing result must not invent a phone association when one host exposes multiple secure connection endpoints"
)

print("PASS: Secure endpoint association refuses ambiguous same-host candidates")

let secondUSBEndpoint = ADBEndpoint(
    identity: DeviceIdentity(serial: "second-usb-exact", displayName: "Second Android phone"),
    authorization: .authorized,
    route: .directUSB,
    provenance: .adbUSBObservation
)
var multiplePhoneCoordinator = ConnectionCoordinator()
multiplePhoneCoordinator.send(
    .discoveryUpdated(
        endpoints: [readyUSBEndpoint, secondUSBEndpoint],
        nearbySecureEndpointCount: 0,
        pairingAvailable: false
    )
)
multiplePhoneCoordinator.send(
    .endpointSelected(serial: secondUSBEndpoint.identity.serial)
)
expectEqual(
    multiplePhoneCoordinator.presentation.workspace,
    .ready(secondUSBEndpoint),
    "The conditional phone chooser must switch the one-device workspace to the selected exact USB endpoint"
)

print("PASS: Connection presentation switches between genuinely distinct USB phones")

let sameNameUSBEndpoint = ADBEndpoint(
    identity: DeviceIdentity(
        serial: "same-name-usb-exact",
        displayName: readyUSBEndpoint.identity.displayName
    ),
    authorization: .authorized,
    route: .directUSB,
    provenance: .adbUSBObservation
)
var ambiguousUSBPhoneCoordinator = ConnectionCoordinator()
ambiguousUSBPhoneCoordinator.send(
    .discoveryUpdated(
        endpoints: [readyUSBEndpoint, sameNameUSBEndpoint],
        nearbySecureEndpointCount: 0,
        pairingAvailable: false
    )
)
expectEqual(
    ambiguousUSBPhoneCoordinator.presentation.workspace,
    .usbDisambiguationRequired(candidateCount: 2),
    "Same-name USB endpoints must require physical disambiguation instead of inventing user-visible phone identities"
)

print("PASS: Connection presentation refuses ambiguous physical-phone labels")

connectionCoordinator.send(
    .legacyTurnedOff(wirelessSerial: verifiedLegacyEndpoint.identity.serial)
)
expectEqual(
    connectionCoordinator.presentation.workspace,
    .ready(readyUSBEndpoint),
    "Turning off legacy Wi-Fi must remove the safe-to-unplug state without affecting the separate USB endpoint"
)

print("PASS: Connection presentation turns off only the proven legacy route")

var legacyLossCoordinator = ConnectionCoordinator()
legacyLossCoordinator.send(
    .discoveryUpdated(
        endpoints: [readyUSBEndpoint],
        nearbySecureEndpointCount: 0,
        pairingAvailable: false
    )
)
legacyLossCoordinator.send(
    .legacySetupStarted(sourceUSBSerial: readyUSBEndpoint.identity.serial)
)
legacyLossCoordinator.send(
    .legacySetupCompleted(
        sourceUSBSerial: readyUSBEndpoint.identity.serial,
        wirelessIdentity: legacyWirelessIdentity
    )
)
legacyLossCoordinator.send(
    .discoveryUpdated(
        endpoints: [readyUSBEndpoint],
        nearbySecureEndpointCount: 0,
        pairingAvailable: false
    )
)
expectEqual(
    legacyLossCoordinator.presentation.workspace,
    .ready(readyUSBEndpoint),
    "A disappeared legacy endpoint must not remain presented as safe to unplug or ready"
)

print("PASS: Connection presentation expires a disappeared legacy endpoint")

var legacyFailureCoordinator = ConnectionCoordinator()
legacyFailureCoordinator.send(
    .discoveryUpdated(
        endpoints: [readyUSBEndpoint],
        nearbySecureEndpointCount: 0,
        pairingAvailable: false
    )
)
legacyFailureCoordinator.send(
    .legacySetupStarted(sourceUSBSerial: readyUSBEndpoint.identity.serial)
)
legacyFailureCoordinator.send(
    .legacySetupFailed(sourceUSBSerial: readyUSBEndpoint.identity.serial)
)
expectEqual(
    legacyFailureCoordinator.presentation.workspace,
    .ready(readyUSBEndpoint),
    "A failed legacy operation must leave the exact USB endpoint ready instead of keeping stale progress"
)

print("PASS: Connection presentation clears legacy progress after failure")

let directoryUSBEndpoint = ADBEndpoint(
    identity: DeviceIdentity(
        serial: "directory-usb-exact",
        displayName: "Everyday Android"
    ),
    authorization: .authorized,
    route: .directUSB,
    provenance: .adbUSBObservation
)
var deviceDirectory = DeviceDirectory()
let connectedDirectory = deviceDirectory.observe(endpoints: [directoryUSBEndpoint])
expectEqual(
    connectedDirectory.connected.map(\.id),
    [.usb(serial: "directory-usb-exact")],
    "An observed USB serial must create one connected Saved Device"
)
expectEqual(
    connectedDirectory.offline.isEmpty,
    true,
    "A currently observed Saved Device must not also appear offline"
)

let offlineDirectory = deviceDirectory.observe(endpoints: [])
expectEqual(
    offlineDirectory.connected.isEmpty,
    true,
    "A Saved Device that disappears must leave the Connected section"
)
expectEqual(
    offlineDirectory.offline.map(\.id),
    [.usb(serial: "directory-usb-exact")],
    "A previously observed USB serial must remain visible as an offline Saved Device"
)
expectEqual(
    offlineDirectory.offline.first?.presence,
    .offline(lastRoute: .usbC),
    "An offline Saved Device must retain its last user-meaningful Connection Route"
)

print("PASS: Device directory retains a disappeared USB device as offline")

let sameNameDirectoryEndpoint = ADBEndpoint(
    identity: DeviceIdentity(
        serial: "directory-second-usb-exact",
        displayName: directoryUSBEndpoint.identity.displayName
    ),
    authorization: .authorized,
    route: .directUSB,
    provenance: .adbUSBObservation
)
let distinctSameNameDirectory = deviceDirectory.observe(
    endpoints: [directoryUSBEndpoint, sameNameDirectoryEndpoint]
)
expectEqual(
    Set(distinctSameNameDirectory.connected.map(\.id)),
    Set([
        .usb(serial: "directory-usb-exact"),
        .usb(serial: "directory-second-usb-exact"),
    ]),
    "Two exact USB serials must remain two Saved Devices even when their display names match"
)

print("PASS: Device directory never merges same-name USB devices")

let directorySecureCandidate = WirelessConnectionCandidate(
    serviceName: "directory-secure-service",
    host: "192.0.2.81",
    port: 38111
)
let directorySecureAddressDevice = DiscoveredDevice(
    identity: DeviceIdentity(
        serial: "192.0.2.81:38111",
        displayName: "Secure Android"
    ),
    state: .authorized,
    transport: .wireless
)
let directorySecureAliasDevice = DiscoveredDevice(
    identity: DeviceIdentity(
        serial: "directory-secure-service._adb-tls-connect._tcp",
        displayName: "Secure Android"
    ),
    state: .authorized,
    transport: .wireless
)
var directoryClassifier = ConnectionEndpointClassifier()
let directorySecureAddressEndpoint = directoryClassifier.endpoint(
    for: directorySecureAddressDevice,
    wirelessCandidates: [directorySecureCandidate]
)
let directorySecureAliasEndpoint = directoryClassifier.endpoint(
    for: directorySecureAliasDevice,
    wirelessCandidates: [directorySecureCandidate]
)
expectEqual(
    directorySecureAliasEndpoint.provenance,
    .secureServiceObservation(serviceName: "directory-secure-service"),
    "The exact ADB mDNS alias may share secure provenance only with its currently observed service"
)

var secureDeviceDirectory = DeviceDirectory()
let secureDirectoryPresentation = secureDeviceDirectory.observe(
    endpoints: [directorySecureAddressEndpoint, directorySecureAliasEndpoint]
)
expectEqual(
    secureDirectoryPresentation.connected.count,
    1,
    "Address and ADB alias endpoints from one exact secure service must produce one Saved Device row"
)
expectEqual(
    secureDirectoryPresentation.connected.first?.endpoints.map(\.identity.serial),
    [
        "192.0.2.81:38111",
        "directory-secure-service._adb-tls-connect._tcp",
    ],
    "A secure Saved Device must retain every exact endpoint required for local disconnect"
)

let secureRecordID = DeviceRecordID.secureService(name: "directory-secure-service")
secureDeviceDirectory.markLocallyDisconnected(secureRecordID)
let locallyDisconnectedDirectory = secureDeviceDirectory.observe(
    endpoints: [directorySecureAddressEndpoint, directorySecureAliasEndpoint]
)
expectEqual(
    locallyDisconnectedDirectory.connected.isEmpty,
    true,
    "Local disconnect must suppress a secure service even if stock ADB advertises it again"
)
expectEqual(
    locallyDisconnectedDirectory.offline.first?.presence,
    .locallyDisconnected(lastRoute: .secureWiFi),
    "Local disconnect must retain the Saved Device with honest Android-trust semantics"
)

print("PASS: Device directory groups and locally suppresses one exact secure service")

let exactDisconnectClient = ADBWirelessConnectionClient(
    adbPath: "/usr/local/bin/adb",
    runner: FixtureCommandRunner(results: [
        "disconnect 192.0.2.81:38111": CommandResult(
            stdout: "disconnected 192.0.2.81:38111",
            stderr: "",
            exitStatus: 0
        ),
    ])
)
try exactDisconnectClient.disconnect(endpoint: directorySecureAddressEndpoint)
expectThrows("Direct USB must never be presented as a disconnectable wireless endpoint") {
    try exactDisconnectClient.disconnect(endpoint: directoryUSBEndpoint)
}

print("PASS: Local disconnect targets only the exact secure wireless endpoint")

let transientWirelessEndpoint = ADBEndpoint(
    identity: DeviceIdentity(
        serial: "192.0.2.99:40999",
        displayName: "Unclassified Android endpoint"
    ),
    authorization: .authorized,
    route: .unclassifiedWireless,
    provenance: .unverified
)
var transientDeviceDirectory = DeviceDirectory()
let transientConnected = transientDeviceDirectory.observe(
    endpoints: [transientWirelessEndpoint]
)
expectEqual(
    transientConnected.connected.map(\.id),
    [.transientEndpoint(serial: "192.0.2.99:40999")],
    "An exact unclassified endpoint may be shown without becoming a Saved Device"
)
transientDeviceDirectory.markLocallyDisconnected(
    .transientEndpoint(serial: "192.0.2.99:40999")
)
let transientSuppressed = transientDeviceDirectory.observe(
    endpoints: [transientWirelessEndpoint]
)
expectEqual(
    transientSuppressed,
    DeviceDirectoryPresentation(connected: [], offline: []),
    "An unclassified exact endpoint must stay suppressed for the session without inventing a persistent device identity"
)

print("PASS: Device directory suppresses an unclassified endpoint only for the session")

let unavailableUSBEndpoint = ADBEndpoint(
    identity: directoryUSBEndpoint.identity,
    authorization: .offline,
    route: .directUSB,
    provenance: .adbUSBObservation
)
let unavailableDirectory = deviceDirectory.observe(endpoints: [unavailableUSBEndpoint])
expectEqual(
    unavailableDirectory.connected.isEmpty,
    true,
    "An ADB-offline endpoint must never receive a connected presentation"
)
expectEqual(
    unavailableDirectory.offline.first(where: {
        $0.id == .usb(serial: "directory-usb-exact")
    })?.presence,
    .offline(lastRoute: .usbC),
    "An observed but unavailable USB endpoint must stay in Offline with its exact route record"
)

print("PASS: Device directory presents ADB-offline endpoints as offline")

var selectedDevicePriorityCoordinator = ConnectionCoordinator()
selectedDevicePriorityCoordinator.send(
    .discoveryUpdated(
        endpoints: [readyUSBEndpoint, secondUSBEndpoint, verifiedLegacyEndpoint],
        nearbySecureEndpointCount: 0,
        pairingAvailable: false
    )
)
selectedDevicePriorityCoordinator.send(
    .endpointSelected(serial: secondUSBEndpoint.identity.serial)
)
expectEqual(
    selectedDevicePriorityCoordinator.presentation.workspace,
    .ready(secondUSBEndpoint),
    "Selecting phone B must not render phone A's separately verified legacy endpoint"
)

print("PASS: Connection presentation prioritizes the selected exact device")

let duplicateSavedRecordID = DeviceRecordID.usb(serial: "duplicate-saved-usb")
let deduplicatedDirectory = DeviceDirectory(savedRecords: [
    SavedDeviceRecord(
        id: duplicateSavedRecordID,
        displayName: "Older name",
        lastRoute: .usbC
    ),
    SavedDeviceRecord(
        id: duplicateSavedRecordID,
        displayName: "Latest name",
        lastRoute: .usbC
    ),
])
expectEqual(
    deduplicatedDirectory.savedRecords,
    [
        SavedDeviceRecord(
            id: duplicateSavedRecordID,
            displayName: "Latest name",
            lastRoute: .usbC
        ),
    ],
    "Duplicate persisted IDs must restore deterministically instead of trapping at launch"
)

private struct PersistedSavedRecordFixture: Encodable {
    let id: DeviceRecordID
    let displayName: String
    let lastRoute: SavedConnectionRoute
    let isLocallyDisconnected: Bool
}

let transientPersistedData = try JSONEncoder().encode([
    PersistedSavedRecordFixture(
        id: .transientEndpoint(serial: "must-not-restore"),
        displayName: "Unsafe transient record",
        lastRoute: .unverifiedWiFi,
        isLocallyDisconnected: true
    ),
])
let decodedTransientRecords = try JSONDecoder().decode(
    [SavedDeviceRecord].self,
    from: transientPersistedData
)
expectEqual(
    DeviceDirectory(savedRecords: decodedTransientRecords).savedRecords,
    [],
    "A decoded transient endpoint must never become a persistent Saved Device"
)

print("PASS: Device directory sanitizes duplicate and transient persisted records")

var legacySelectionTransitionCoordinator = ConnectionCoordinator()
legacySelectionTransitionCoordinator.send(
    .discoveryUpdated(
        endpoints: [readyUSBEndpoint],
        nearbySecureEndpointCount: 0,
        pairingAvailable: false
    )
)
legacySelectionTransitionCoordinator.send(
    .endpointSelected(serial: readyUSBEndpoint.identity.serial)
)
legacySelectionTransitionCoordinator.send(
    .legacySetupStarted(sourceUSBSerial: readyUSBEndpoint.identity.serial)
)
legacySelectionTransitionCoordinator.send(
    .legacySetupCompleted(
        sourceUSBSerial: readyUSBEndpoint.identity.serial,
        wirelessIdentity: legacyWirelessIdentity
    )
)
expectEqual(
    legacySelectionTransitionCoordinator.presentation.workspace,
    .legacySafeToUnplug(verifiedLegacyEndpoint),
    "Completing USB-assisted setup must move exact selection from USB to the verified wireless endpoint"
)

print("PASS: Legacy completion selects the exact verified wireless endpoint")

let secureConnectionPanel = ConnectionPanelPresentation(
    route: .secureWirelessDebugging
)
expectEqual(
    secureConnectionPanel,
    ConnectionPanelPresentation(
        title: "Wireless Debugging",
        status: "Connected securely",
        security: "Encrypted by Android",
        lifecycle: "Disconnecting here closes only this Mac's current connection. Android may continue to remember this Mac.",
        management: .disconnectOnThisMac
    ),
    "Secure Wireless Debugging must explain its security, local disconnect scope, and persistent Android trust"
)

let legacyConnectionPanel = ConnectionPanelPresentation(
    route: .legacyWirelessUntilRestart
)
expectEqual(
    legacyConnectionPanel,
    ConnectionPanelPresentation(
        title: "Wi-Fi until restart",
        status: "Connected",
        security: "Unencrypted on your local network",
        lifecycle: "Turn it off here or restart the phone to close the wireless ADB listener.",
        management: .turnOffWirelessUntilRestart
    ),
    "USB-assisted Wi-Fi must distinguish its unencrypted transport and explicit turn-off lifecycle"
)

let directUSBConnectionPanel = ConnectionPanelPresentation(route: .directUSB)
expectEqual(
    directUSBConnectionPanel.management,
    .unplugUSB,
    "Direct USB management must remain an honest unplug action instead of an invented software disconnect"
)

let unverifiedConnectionPanel = ConnectionPanelPresentation(
    route: .unclassifiedWireless
)
expectEqual(
    unverifiedConnectionPanel.management,
    .disconnectUnverifiedEndpoint,
    "An unverified endpoint may expose only exact-endpoint local disconnect semantics"
)

print("PASS: Connection panels preserve route-specific security and management semantics")

let accessibilityFixtureProfile = UIFixturePresentationProfile(environment: [
    "TETHERPANE_UI_FIXTURE": "device-management",
    "TETHERPANE_UI_APPEARANCE": "light",
    "TETHERPANE_UI_REDUCE_MOTION": "true",
    "TETHERPANE_UI_REDUCE_TRANSPARENCY": "1",
])
expectEqual(
    accessibilityFixtureProfile.appearance,
    .light,
    "A visual QA fixture must be able to request Light appearance without changing macOS settings"
)
expectEqual(
    accessibilityFixtureProfile.reduceMotion,
    true,
    "A visual QA fixture must be able to replace spring motion with its reduced-motion path"
)
expectEqual(
    accessibilityFixtureProfile.reduceTransparency,
    true,
    "A visual QA fixture must be able to ask system materials for reduced transparency"
)

let normalLaunchPresentationProfile = UIFixturePresentationProfile(environment: [
    "TETHERPANE_UI_APPEARANCE": "light",
    "TETHERPANE_UI_REDUCE_MOTION": "true",
])
expectEqual(
    normalLaunchPresentationProfile,
    .system,
    "Presentation overrides must not affect a normal launch"
)

let unknownFixturePresentationProfile = UIFixturePresentationProfile(environment: [
    "TETHERPANE_UI_FIXTURE": "unknown-fixture",
    "TETHERPANE_UI_APPEARANCE": "light",
    "TETHERPANE_UI_REDUCE_TRANSPARENCY": "true",
])
expectEqual(
    unknownFixturePresentationProfile,
    .system,
    "Presentation overrides must not activate for an unrecognized fixture"
)

let invalidAccessibilityFixtureProfile = UIFixturePresentationProfile(environment: [
    "TETHERPANE_UI_FIXTURE": "device-management",
    "TETHERPANE_UI_APPEARANCE": "sepia",
    "TETHERPANE_UI_REDUCE_MOTION": "sometimes",
])
expectEqual(
    invalidAccessibilityFixtureProfile,
    .system,
    "Unrecognized fixture values must preserve the user's real system presentation settings"
)

print("PASS: UI fixture presentation overrides are typed, opt-in, and system-preserving by default")
