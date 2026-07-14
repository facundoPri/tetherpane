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

let qrPairingSession = WirelessQRCodePairingSession(
    serviceName: "studio-AirDroid1",
    password: "0123456789"
)
expectEqual(
    qrPairingSession.payload,
    "WIFI:T:ADB;S:studio-AirDroid1;P:0123456789;;",
    "QR pairing must encode the ADB service name and one-time secret in Android's Wireless Debugging format"
)

print("PASS: QR pairing produces Android's literal Wireless Debugging payload")

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

    func launch(executable: String, arguments: [String]) throws -> any RunningProcess {
        launches.append((executable, arguments))
        return process
    }
}

let processLauncher = FixtureProcessLauncher()
let mirroringEngine = ScrcpyMirroringEngine(
    scrcpyPath: "/usr/local/bin/scrcpy",
    launcher: processLauncher
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
mirroringEngine.stop()
expectEqual(processLauncher.process.terminateWasRequested, true, "Stopping must terminate the launched child process")
expectEqual(mirroringEngine.state, .stopped, "Stopping must expose a stopped lifecycle state")
_ = try mirroringEngine.start(configuration: highQualityConfiguration)
expectEqual(processLauncher.launches.count, 2, "A stopped session must permit an exact-device reconnect")
expectEqual(lifecycleTransitions.contains(.stopped), true, "Lifecycle consumers must observe an explicit stopped state")

print("PASS: Mirroring engine launches, stops, and reconnects the exact typed scrcpy session")

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

    func launch(executable: String, arguments: [String]) throws -> any RunningProcess {
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

print("PASS: Mirroring engine surfaces an unexpected child-process exit")
