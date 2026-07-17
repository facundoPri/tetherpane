import AirDroidDomain
import AirDroidScrcpy
import Foundation
import TetherPaneUIFixtureSupport

enum LiveWirelessConnectionClient {
    static func make() -> any WirelessConnectionClient {
        if UIFixture.active != nil {
            return UIFixtureWirelessConnectionClient()
        }
        guard let adbPath = DeveloperToolPathResolver.adbPath() else {
            return UnavailableWirelessConnectionClient(
                message: DeveloperToolInstallationGuidance.adbUnavailable
            )
        }
        return ADBWirelessConnectionClient(adbPath: adbPath, runner: ProcessCommandRunner())
    }
}

private struct UIFixtureWirelessConnectionClient: WirelessConnectionClient {
    func connect(candidate: WirelessConnectionCandidate) throws -> WirelessConnection {
        throw UIFixtureActionError()
    }

    func connectOverTCPIP(device: DeviceIdentity) throws -> WirelessConnection {
        throw UIFixtureActionError()
    }

    func openDeveloperOptions(device: DeviceIdentity) throws {
        throw UIFixtureActionError()
    }

    func disableTCPIP(endpoint: ADBEndpoint) throws {
        throw UIFixtureActionError()
    }

    func disconnect(endpoint: ADBEndpoint) throws {
        throw UIFixtureActionError()
    }
}

private struct UnavailableWirelessConnectionClient: WirelessConnectionClient {
    let message: String

    func connect(candidate: WirelessConnectionCandidate) throws -> WirelessConnection {
        throw WirelessConnectionUnavailableError(message: message)
    }

    func connectOverTCPIP(device: DeviceIdentity) throws -> WirelessConnection {
        throw WirelessConnectionUnavailableError(message: message)
    }

    func openDeveloperOptions(device: DeviceIdentity) throws {
        throw WirelessConnectionUnavailableError(message: message)
    }

    func disableTCPIP(endpoint: ADBEndpoint) throws {
        throw WirelessConnectionUnavailableError(message: message)
    }

    func disconnect(endpoint: ADBEndpoint) throws {
        throw WirelessConnectionUnavailableError(message: message)
    }
}

private struct WirelessConnectionUnavailableError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
