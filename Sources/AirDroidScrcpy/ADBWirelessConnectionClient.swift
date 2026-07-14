import AirDroidDomain
import Foundation

public enum ADBWirelessConnectionClientError: LocalizedError {
    case connectionFailed
    case wifiAddressUnavailable
    case tcpipEnablementFailed
    case tcpipDisablementFailed
    case disconnectUnsupported
    case disconnectFailed
    case developerOptionsUnavailable

    public var errorDescription: String? {
        switch self {
        case .connectionFailed:
            "Could not connect over Wi-Fi. Keep Wireless Debugging open on the phone, confirm both devices are on the same network, then try again."
        case .wifiAddressUnavailable:
            "The phone has no usable Wi-Fi address. Connect it to the same Wi-Fi network as this Mac, keep USB attached, then try again."
        case .tcpipEnablementFailed:
            "Could not enable temporary ADB over TCP/IP on this USB device. Reauthorize USB debugging on the phone, then try again."
        case .tcpipDisablementFailed:
            "Could not turn off USB-assisted Wi-Fi on this phone. Keep the phone reachable, stop mirroring, then try again."
        case .disconnectUnsupported:
            "This connection cannot be disconnected here. Unplug USB connections, or use Turn Off for USB-assisted Wi-Fi."
        case .disconnectFailed:
            "Could not disconnect this wireless endpoint on the Mac. It remains authorized in Android and may reconnect while Wireless Debugging is enabled."
        case .developerOptionsUnavailable:
            "Could not open Developer Options on this device. Unlock the phone and open Settings → System → Developer options manually."
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
        guard try connect(serial: serial) else {
            throw ADBWirelessConnectionClientError.connectionFailed
        }

        return WirelessConnection(deviceSerial: serial)
    }

    public func connectOverTCPIP(device: DeviceIdentity) throws -> WirelessConnection {
        let addressResult = try runner.run(
            executable: adbPath,
            arguments: ["-s", device.serial, "shell", "ip", "-f", "inet", "addr", "show", "wlan0"]
        )
        let address: String?
        if addressResult.exitStatus == 0,
           let wlan0Address = interfaceIPv4Address(in: addressResult.stdout) {
            address = wlan0Address
        } else {
            let routeResult = try runner.run(
                executable: adbPath,
                arguments: ["-s", device.serial, "shell", "ip", "-4", "route"]
            )
            address = routeResult.exitStatus == 0
                ? routedIPv4Address(in: routeResult.stdout)
                : nil
        }
        guard let address else {
            throw ADBWirelessConnectionClientError.wifiAddressUnavailable
        }

        let port = 5555
        let tcpipResult = try runner.run(
            executable: adbPath,
            arguments: ["-s", device.serial, "tcpip", String(port)]
        )
        guard commandSucceeded(tcpipResult) else {
            throw ADBWirelessConnectionClientError.tcpipEnablementFailed
        }

        let serial = endpoint(host: address, port: port)
        guard try connect(serial: serial) else {
            throw ADBWirelessConnectionClientError.connectionFailed
        }
        return WirelessConnection(deviceSerial: serial)
    }

    public func openDeveloperOptions(device: DeviceIdentity) throws {
        let result = try runner.run(
            executable: adbPath,
            arguments: [
                "-s", device.serial,
                "shell", "am", "start",
                "-a", "android.settings.APPLICATION_DEVELOPMENT_SETTINGS",
            ]
        )
        guard commandSucceeded(result) else {
            throw ADBWirelessConnectionClientError.developerOptionsUnavailable
        }
    }

    public func disableTCPIP(endpoint: ADBEndpoint) throws {
        let result = try runner.run(
            executable: adbPath,
            arguments: ["-s", endpoint.identity.serial, "usb"]
        )
        guard commandSucceeded(result) else {
            throw ADBWirelessConnectionClientError.tcpipDisablementFailed
        }
        if endpoint.route != .directUSB {
            _ = try? runner.run(
                executable: adbPath,
                arguments: ["disconnect", endpoint.identity.serial]
            )
        }
    }

    public func disconnect(endpoint: ADBEndpoint) throws {
        guard endpoint.route == .secureWirelessDebugging
                || endpoint.route == .unclassifiedWireless
        else {
            throw ADBWirelessConnectionClientError.disconnectUnsupported
        }
        let result = try runner.run(
            executable: adbPath,
            arguments: ["disconnect", endpoint.identity.serial]
        )
        guard commandSucceeded(result) else {
            throw ADBWirelessConnectionClientError.disconnectFailed
        }
    }

    private func connect(serial: String) throws -> Bool {
        let result = try runner.run(
            executable: adbPath,
            arguments: ["connect", serial]
        )
        return commandSucceeded(result)
    }

    private func commandSucceeded(_ result: CommandResult) -> Bool {
        let output = "\(result.stdout)\n\(result.stderr)".lowercased()
        return result.exitStatus == 0
            && !output.contains("failed")
            && !output.contains("unable")
            && !output.contains("cannot connect")
            && !output.contains("error:")
    }

    private func interfaceIPv4Address(in output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard let inetIndex = fields.firstIndex(of: "inet"),
                  fields.indices.contains(inetIndex + 1)
            else {
                continue
            }
            let address = String(fields[inetIndex + 1].split(separator: "/", maxSplits: 1)[0])
            if isIPv4Address(address) { return address }
        }
        return nil
    }

    private func routedIPv4Address(in output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard let sourceIndex = fields.firstIndex(of: "src"),
                  fields.indices.contains(sourceIndex + 1)
            else {
                continue
            }
            let address = String(fields[sourceIndex + 1])
            if isIPv4Address(address) { return address }
        }
        return nil
    }

    private func isIPv4Address(_ address: String) -> Bool {
        let octets = address.split(separator: ".")
        return octets.count == 4 && octets.allSatisfy { octet in
            guard let value = Int(octet) else { return false }
            return (0...255).contains(value)
        }
    }

    private func endpoint(host: String, port: Int) -> String {
        ADBNetworkEndpoint(host: host, port: port).adbAddress
    }
}
