import AirDroidDomain

public struct ScrcpyInvocation: Equatable, Sendable {
    public let arguments: [String]

    public init(arguments: [String]) {
        self.arguments = arguments
    }
}

public struct ScrcpyCommandBuilder: Sendable {
    public init() {}

    public func build(configuration: MirroringConfiguration) -> ScrcpyInvocation {
        var arguments = ["--serial=\(configuration.device.serial)"]

        switch configuration.preset {
        case .responsive:
            arguments += [
                "--video-codec=h264",
                "--max-size=1280",
                "--max-fps=60",
                "--video-bit-rate=8M",
            ]
        case .highQuality:
            arguments += [
                "--video-codec=h265",
                "--max-size=1920",
                "--max-fps=60",
                "--video-bit-rate=16M",
            ]
        }

        if !configuration.audioEnabled {
            arguments.append("--no-audio")
        }

        if let recordingURL = configuration.recordingURL {
            arguments.append("--record=\(recordingURL.path())")
        }

        arguments.append("--window-title=\(configuration.device.displayName)")
        return ScrcpyInvocation(arguments: arguments)
    }
}
