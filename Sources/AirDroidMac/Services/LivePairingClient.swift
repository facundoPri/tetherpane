import AirDroidDomain
import AirDroidScrcpy
import Foundation

enum LivePairingClient {
    static func make() -> any PairingClient {
        if UIFixture.active != nil {
            return UIFixturePairingClient()
        }
        guard let adbPath = DeveloperToolPathResolver.adbPath() else {
            return UnavailablePairingClient(
                message: DeveloperToolInstallationGuidance.adbUnavailable
            )
        }
        return ADBPairingClient(adbPath: adbPath, runner: ProcessCommandRunner())
    }
}

private struct UIFixturePairingClient: PairingClient {
    func pair(candidate: PairingCandidate, code: String) throws {
        throw UIFixtureActionError()
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
