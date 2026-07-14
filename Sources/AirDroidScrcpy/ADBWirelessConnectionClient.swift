import AirDroidDomain
import Foundation

public enum ADBWirelessConnectionClientError: LocalizedError {
    case connectionFailed

    public var errorDescription: String? {
        switch self {
        case .connectionFailed:
            "Could not connect over Wi-Fi. Keep Wireless Debugging open on the phone, confirm both devices are on the same network, then try again."
        }
    }
}

public struct ADBWirelessConnectionClient<Runner: CommandRunning>: WirelessConnectionClient {
    private let adbPath: String
    private let runner: Runner

    public init(adbPath: String, runner: Runner) {
        self.adbPath = adbPath
        self.runner = runner
    }

    public func connect(candidate: WirelessConnectionCandidate) throws -> WirelessConnection {
        let serial = endpoint(host: candidate.host, port: candidate.port)
        let result = try runner.run(
            executable: adbPath,
            arguments: ["connect", serial]
        )
        let output = "\(result.stdout)\n\(result.stderr)".lowercased()
        guard result.exitStatus == 0,
              !output.contains("failed"),
              !output.contains("unable"),
              !output.contains("cannot connect")
        else {
            throw ADBWirelessConnectionClientError.connectionFailed
        }

        return WirelessConnection(deviceSerial: serial)
    }

    private func endpoint(host: String, port: Int) -> String {
        let formattedHost = host.contains(":") ? "[\(host)]" : host
        return "\(formattedHost):\(port)"
    }
}
