import AirDroidDomain
import Foundation
import OSLog

public protocol RunningProcess: AnyObject {
    var isRunning: Bool { get }
    func terminate()
    func observeTermination(_ handler: @escaping @Sendable (Int32) -> Void)
}

public protocol ProcessLaunching: Sendable {
    func launch(executable: String, arguments: [String]) throws -> any RunningProcess
}

@MainActor
public protocol MirroringEngine: AnyObject {
    var state: MirroringSessionState { get }
    var stateDidChange: ((MirroringSessionState) -> Void)? { get set }
    func start(configuration: MirroringConfiguration) throws -> ScrcpyInvocation
    func stop()
}

public enum ScrcpyMirroringEngineError: LocalizedError {
    case sessionAlreadyRunning

    public var errorDescription: String? {
        switch self {
        case .sessionAlreadyRunning:
            "A scrcpy session is already running. Stop it before starting another one."
        }
    }
}

@MainActor
public final class ScrcpyMirroringEngine<Launcher: ProcessLaunching>: MirroringEngine {
    public private(set) var state: MirroringSessionState = .idle
    public var stateDidChange: ((MirroringSessionState) -> Void)?

    private let scrcpyPath: String
    private let launcher: Launcher
    private let commandBuilder: ScrcpyCommandBuilder
    private let logger = Logger(subsystem: "com.facundopri.airdroid.spike", category: "Mirroring")
    private var runningProcess: (any RunningProcess)?
    private var activeSessionID: UUID?

    public init(
        scrcpyPath: String,
        launcher: Launcher,
        commandBuilder: ScrcpyCommandBuilder = ScrcpyCommandBuilder()
    ) {
        self.scrcpyPath = scrcpyPath
        self.launcher = launcher
        self.commandBuilder = commandBuilder
    }

    public func start(configuration: MirroringConfiguration) throws -> ScrcpyInvocation {
        guard runningProcess == nil else {
            throw ScrcpyMirroringEngineError.sessionAlreadyRunning
        }

        transition(to: .starting(configuration.device))
        let invocation = commandBuilder.build(configuration: configuration)
        logger.info(
            "scrcpy start requested preset=\(configuration.preset.rawValue, privacy: .public) audio=\(configuration.audioEnabled, privacy: .public) recording=\(configuration.recordingURL != nil, privacy: .public)"
        )

        do {
            let sessionID = UUID()
            let process = try launcher.launch(executable: scrcpyPath, arguments: invocation.arguments)
            runningProcess = process
            activeSessionID = sessionID
            process.observeTermination { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.handleTermination(sessionID: sessionID, status: status)
                }
            }
            transition(to: .mirroring(configuration.device))
            logger.info("scrcpy session started")
            return invocation
        } catch {
            activeSessionID = nil
            transition(to: .failed("Could not start scrcpy: \(error.localizedDescription)"))
            logger.error("scrcpy session failed to start")
            throw error
        }
    }

    public func stop() {
        guard let process = runningProcess else {
            transition(to: .stopped)
            return
        }

        logger.info("scrcpy stop requested")
        activeSessionID = nil
        runningProcess = nil
        if process.isRunning {
            process.terminate()
        }
        transition(to: .stopped)
        logger.info("scrcpy session stopped")
    }

    private func handleTermination(sessionID: UUID, status: Int32) {
        guard activeSessionID == sessionID else { return }

        activeSessionID = nil
        runningProcess = nil
        transition(to: .failed("scrcpy stopped unexpectedly (exit \(status)). Reconnect to try again."))
        logger.error("scrcpy session ended unexpectedly exitStatus=\(status, privacy: .public)")
    }

    private func transition(to nextState: MirroringSessionState) {
        state = nextState
        stateDidChange?(nextState)
    }
}

public final class FoundationRunningProcess: RunningProcess, @unchecked Sendable {
    private let process: Process
    private var terminationHandler: (@Sendable (Int32) -> Void)?

    init(process: Process) {
        self.process = process
    }

    public var isRunning: Bool { process.isRunning }

    public func terminate() {
        process.terminate()
    }

    public func observeTermination(_ handler: @escaping @Sendable (Int32) -> Void) {
        terminationHandler = handler
        process.terminationHandler = { [weak self] process in
            self?.terminationHandler?(process.terminationStatus)
        }
    }
}

public struct FoundationProcessLauncher: ProcessLaunching {
    public init() {}

    public func launch(executable: String, arguments: [String]) throws -> any RunningProcess {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        try process.run()
        return FoundationRunningProcess(process: process)
    }
}
