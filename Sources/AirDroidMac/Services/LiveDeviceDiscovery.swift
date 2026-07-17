import AirDroidDomain
import AirDroidScrcpy
import Foundation
import TetherPaneUIFixtureSupport

enum LiveDeviceDiscovery {
    static func make() -> any DeviceDiscovery {
        if let fixture = UIFixture.active {
            return FixtureDeviceDiscovery(snapshot: fixture.scenario.discoverySnapshot)
        }
        guard let adbPath = DeveloperToolPathResolver.adbPath() else {
            return UnavailableDeviceDiscovery(
                message: DeveloperToolInstallationGuidance.adbUnavailable
            )
        }
        return ADBDeviceDiscovery(adbPath: adbPath, runner: ProcessCommandRunner())
    }
}

private struct FixtureDeviceDiscovery: DeviceDiscovery {
    let snapshot: DeviceDiscoverySnapshot

    func discover() throws -> DeviceDiscoverySnapshot {
        snapshot
    }
}

private struct UnavailableDeviceDiscovery: DeviceDiscovery {
    let message: String

    func discover() throws -> DeviceDiscoverySnapshot {
        throw DeviceDiscoverySetupError(message: message)
    }
}

private struct DeviceDiscoverySetupError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
