import AirDroidDomain
import AirDroidScrcpy
import Foundation

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

final class RecordingCommandRunner: StandardInputCommandRunning {
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

final class OrderedCommandRunner: CommandRunning {
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
    device: DeviceIdentity(serial: "192.168.1.44:5555", displayName: "Motorola edge 40 pro")
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

final class FixtureRunningProcess: RunningProcess {
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
    private var outputHandler: (@Sendable (ScrcpyProcessOutput) -> Void)?

    func launch(
        executable: String,
        arguments: [String],
        outputHandler: @escaping @Sendable (ScrcpyProcessOutput) -> Void
    ) throws -> any RunningProcess {
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

let launchedInvocation = try mirroringEngine.start(configuration: highQualityConfiguration)
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
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
expectEqual(
    mirroringEngine.diagnostics.recentLines,
    [
        ScrcpyDiagnosticLine(channel: .standardOutput, message: "INFO: renderer ready"),
        ScrcpyDiagnosticLine(channel: .standardError, message: "WARN: audio fallback"),
        ScrcpyDiagnosticLine(channel: .standardError, message: "ERROR: final diagnostic"),
    ],
    "Mirroring diagnostics must retain a bounded, ordered tail of scrcpy output"
)
mirroringEngine.stop()
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
expectEqual(processLauncher.process.terminateWasRequested, true, "Stopping must terminate the launched child process")
expectEqual(mirroringEngine.state, .stopped, "Stopping must expose a stopped lifecycle state")
expectEqual(mirroringEngine.diagnostics.lastExitStatus, 0, "Diagnostics must retain the expected child exit status")
_ = try mirroringEngine.start(configuration: highQualityConfiguration)
expectEqual(processLauncher.launches.count, 2, "A stopped session must permit an exact-device reconnect")
expectEqual(lifecycleTransitions.contains(.stopped), true, "Lifecycle consumers must observe an explicit stopped state")
expectEqual(mirroringEngine.diagnostics.recentLines, [], "A reconnect must begin with a fresh diagnostic tail")

print("PASS: Mirroring engine launches, diagnoses, stops, and reconnects the exact typed scrcpy session")

final class UnexpectedExitProcess: RunningProcess {
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
_ = try unexpectedExitEngine.start(configuration: highQualityConfiguration)
unexpectedExitLauncher.process.finish(status: 70)
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
expectEqual(
    unexpectedExitEngine.state,
    .failed("scrcpy stopped unexpectedly (exit 70). Reconnect to try again."),
    "An unexpected child exit must surface a reconnectable typed error state"
)
expectEqual(unexpectedExitTransition, unexpectedExitEngine.state, "Lifecycle consumers must observe an unexpected exit")
expectEqual(unexpectedExitEngine.diagnostics.lastExitStatus, 70, "Unexpected exit diagnostics must retain the exact status")

print("PASS: Mirroring engine surfaces an unexpected child-process exit")
