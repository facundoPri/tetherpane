import AirDroidDomain
import Foundation

public struct CommandResult: Equatable, Sendable {
    public let stdout: String
    public let stderr: String
    public let exitStatus: Int32

    public init(stdout: String, stderr: String, exitStatus: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitStatus = exitStatus
    }
}

public protocol CommandRunning {
    func run(executable: String, arguments: [String]) throws -> CommandResult
}

public protocol StandardInputCommandRunning: CommandRunning {
    func run(
        executable: String,
        arguments: [String],
        standardInput: String
    ) throws -> CommandResult
}

public enum ADBDeviceDiscoveryError: LocalizedError {
    case commandFailed(arguments: [String], message: String)

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(arguments, message):
            "ADB \(arguments.joined(separator: " ")) failed: \(message)"
        }
    }
}

public struct ADBDeviceDiscovery<Runner: CommandRunning>: DeviceDiscovery {
    private let adbPath: String
    private let runner: Runner

    public init(adbPath: String, runner: Runner) {
        self.adbPath = adbPath
        self.runner = runner
    }

    public func discover() throws -> DeviceDiscoverySnapshot {
        let devices = try command(arguments: ["devices", "-l"])
        let mdns = try command(arguments: ["mdns", "services"])
        let wirelessConnectionCandidates = parseWirelessConnectionCandidates(mdns.stdout)

        return DeviceDiscoverySnapshot(
            devices: removeDuplicateWirelessAliases(
                from: parseDevices(devices.stdout),
                candidates: wirelessConnectionCandidates
            ),
            pairingCandidates: parsePairingCandidates(mdns.stdout),
            wirelessConnectionCandidates: wirelessConnectionCandidates
        )
    }

    private func command(arguments: [String]) throws -> CommandResult {
        let result = try runner.run(executable: adbPath, arguments: arguments)
        guard result.exitStatus == 0 else {
            let reportedMessage = result.stderr.isEmpty ? result.stdout : result.stderr
            let message = reportedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ADBDeviceDiscoveryError.commandFailed(
                arguments: arguments,
                message: message.isEmpty
                    ? "command exited with status \(result.exitStatus) without output."
                    : message
            )
        }
        return result
    }

    private func parseDevices(_ output: String) -> [DiscoveredDevice] {
        output
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .compactMap { line in
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.count >= 2 else { return nil }

                let serial = String(fields[0])
                let state = connectionState(rawValue: String(fields[1]))
                let model = fields
                    .first(where: { $0.hasPrefix("model:") })
                    .map { String($0.dropFirst("model:".count)).replacingOccurrences(of: "_", with: " ") }
                    ?? serial

                return DiscoveredDevice(
                    identity: DeviceIdentity(serial: serial, displayName: model),
                    state: state,
                    transport: connectionTransport(serial: serial, fields: fields)
                )
            }
    }

    private func connectionTransport(
        serial: String,
        fields: [Substring]
    ) -> DeviceTransport {
        if fields.contains(where: { $0.hasPrefix("usb:") }) {
            return .usb
        }
        if serial.hasPrefix("emulator-") {
            return .emulator
        }
        if serial.contains(":") || serial.contains("_adb-tls-connect._tcp") {
            return .wireless
        }
        return .unknown
    }

    private func connectionState(rawValue: String) -> DeviceConnectionState {
        switch rawValue {
        case "device": .authorized
        case "offline": .offline
        case "unauthorized": .unauthorized
        default: .unknown(rawValue)
        }
    }

    private func parsePairingCandidates(_ output: String) -> [PairingCandidate] {
        output
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .compactMap { line in
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.count >= 3,
                      fields[1].contains("_adb-tls-pairing._tcp"),
                      let endpoint = endpoint(from: String(fields[2]))
                else {
                    return nil
                }

                return PairingCandidate(
                    serviceName: String(fields[0]),
                    host: endpoint.host,
                    port: endpoint.port
                )
            }
    }

    private func parseWirelessConnectionCandidates(_ output: String) -> [WirelessConnectionCandidate] {
        output
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .compactMap { line in
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.count >= 3,
                      fields[1].contains("_adb-tls-connect._tcp"),
                      let endpoint = endpoint(from: String(fields[2]))
                else {
                    return nil
                }

                return WirelessConnectionCandidate(
                    serviceName: String(fields[0]),
                    host: endpoint.host,
                    port: endpoint.port
                )
            }
    }

    private func removeDuplicateWirelessAliases(
        from devices: [DiscoveredDevice],
        candidates: [WirelessConnectionCandidate]
    ) -> [DiscoveredDevice] {
        let serviceAliasesToDrop = Set(candidates.compactMap { candidate -> String? in
            let exactEndpoint = endpoint(host: candidate.host, port: candidate.port)
            guard devices.contains(where: { $0.identity.serial == exactEndpoint }) else {
                return nil
            }
            return "\(candidate.serviceName)._adb-tls-connect._tcp"
        })

        return devices.filter { device in
            !serviceAliasesToDrop.contains(device.identity.serial)
        }
    }

    private func endpoint(host: String, port: Int) -> String {
        let formattedHost = host.contains(":") ? "[\(host)]" : host
        return "\(formattedHost):\(port)"
    }

    private func endpoint(from value: String) -> (host: String, port: Int)? {
        guard let separator = value.lastIndex(of: ":"),
              let port = Int(value[value.index(after: separator)...])
        else {
            return nil
        }

        return (String(value[..<separator]), port)
    }
}

public struct ProcessCommandRunner: StandardInputCommandRunning {
    public init() {}

    public func run(executable: String, arguments: [String]) throws -> CommandResult {
        try runProcess(executable: executable, arguments: arguments, standardInput: nil)
    }

    public func run(
        executable: String,
        arguments: [String],
        standardInput: String
    ) throws -> CommandResult {
        try runProcess(
            executable: executable,
            arguments: arguments,
            standardInput: standardInput
        )
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        standardInput: String?
    ) throws -> CommandResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = standardInput == nil ? nil : Pipe()

        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin
        try process.run()
        if let standardInput, let stdin {
            stdin.fileHandleForWriting.write(Data(standardInput.utf8))
            try stdin.fileHandleForWriting.close()
        }
        process.waitUntilExit()

        return CommandResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitStatus: process.terminationStatus
        )
    }
}
