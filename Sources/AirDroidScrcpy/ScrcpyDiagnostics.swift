public enum ScrcpyOutputChannel: String, Hashable, Sendable {
    case standardOutput
    case standardError
}

public struct ScrcpyProcessOutput: Equatable, Sendable {
    public let channel: ScrcpyOutputChannel
    public let text: String

    public init(channel: ScrcpyOutputChannel, text: String) {
        self.channel = channel
        self.text = text
    }
}

public struct ScrcpyDiagnosticLine: Equatable, Sendable {
    public let channel: ScrcpyOutputChannel
    public let message: String

    public init(channel: ScrcpyOutputChannel, message: String) {
        self.channel = channel
        self.message = message
    }
}

public struct ScrcpyDiagnostics: Equatable, Sendable {
    public let recentLines: [ScrcpyDiagnosticLine]
    public let lastExitStatus: Int32?

    public init(
        recentLines: [ScrcpyDiagnosticLine] = [],
        lastExitStatus: Int32? = nil
    ) {
        self.recentLines = recentLines
        self.lastExitStatus = lastExitStatus
    }
}
