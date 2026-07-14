import AirDroidDomain
import AirDroidScrcpy
import Foundation

enum LiveWirelessConnectionClient {
    static func make() -> any WirelessConnectionClient {
        guard let adbPath = DeveloperToolPathResolver.adbPath() else {
            return UnavailableWirelessConnectionClient(
                message: "ADB is not installed. Run make bootstrap or set ADB_PATH."
            )
        }
        return ADBWirelessConnectionClient(adbPath: adbPath, runner: ProcessCommandRunner())
    }
}

private struct UnavailableWirelessConnectionClient: WirelessConnectionClient {
    let message: String

    func connect(candidate: WirelessConnectionCandidate) throws -> WirelessConnection {
        throw WirelessConnectionUnavailableError(message: message)
    }
}

private struct WirelessConnectionUnavailableError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
