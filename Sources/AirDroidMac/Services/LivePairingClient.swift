import AirDroidDomain
import AirDroidScrcpy
import Foundation

enum LivePairingClient {
    static func make() -> any PairingClient {
        guard let adbPath = DeveloperToolPathResolver.adbPath() else {
            return UnavailablePairingClient(message: "ADB is not installed. Run make bootstrap or set ADB_PATH.")
        }
        return ADBPairingClient(adbPath: adbPath, runner: ProcessCommandRunner())
    }
}

private struct UnavailablePairingClient: PairingClient {
    let message: String

    func pair(candidate: PairingCandidate, code: String) throws {
        throw PairingUnavailableError(message: message)
    }
}

private struct PairingUnavailableError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
