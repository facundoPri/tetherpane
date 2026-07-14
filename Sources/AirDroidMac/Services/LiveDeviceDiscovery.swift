import AirDroidDomain
import AirDroidScrcpy
import Foundation

enum LiveDeviceDiscovery {
    static func make() -> any DeviceDiscovery {
        guard let adbPath = DeveloperToolPathResolver.adbPath() else {
            return UnavailableDeviceDiscovery(message: "ADB is not installed. Run make bootstrap or set ADB_PATH.")
        }
        return ADBDeviceDiscovery(adbPath: adbPath, runner: ProcessCommandRunner())
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
