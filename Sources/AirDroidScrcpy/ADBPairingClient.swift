import AirDroidDomain
import Foundation

public enum ADBPairingClientError: LocalizedError {
    case invalidCode
    case pairingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidCode:
            "Enter the pairing code shown by Android before continuing."
        case .pairingFailed:
            "Wireless Debugging pairing did not succeed. Confirm that this code is still visible on the phone, then try again."
        }
    }
}

public struct ADBPairingClient<Runner: StandardInputCommandRunning>: PairingClient {
    private let adbPath: String
    private let runner: Runner

    public init(adbPath: String, runner: Runner) {
        self.adbPath = adbPath
        self.runner = runner
    }

    public func pair(candidate: PairingCandidate, code: String) throws {
        let oneShotCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oneShotCode.isEmpty else {
            throw ADBPairingClientError.invalidCode
        }

        let result = try runner.run(
            executable: adbPath,
            arguments: ["pair", endpoint(for: candidate)],
            standardInput: "\(oneShotCode)\n"
        )
        let output = "\(result.stdout)\n\(result.stderr)".lowercased()
        guard result.exitStatus == 0,
              output.contains("successfully paired")
        else {
            throw ADBPairingClientError.pairingFailed
        }
    }

    private func endpoint(for candidate: PairingCandidate) -> String {
        let host = candidate.host.contains(":") ? "[\(candidate.host)]" : candidate.host
        return "\(host):\(candidate.port)"
    }
}
