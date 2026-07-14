import AirDroidDomain
import Foundation
import OSLog

public protocol RunningProcess: AnyObject {
    var isRunning: Bool { get }
    func terminate()
    func observeTermination(_ handler: @escaping @Sendable (Int32) -> Void)
}

public protocol ProcessLaunching: Sendable {
    func launch(
        executable: String,
        arguments: [String],
        outputHandler: @escaping @Sendable (ScrcpyProcessOutput) -> Void
    ) throws -> any RunningProcess
}

@MainActor
public protocol MirroringEngine: AnyObject {
    var state: MirroringSessionState { get }
    var stateDidChange: ((MirroringSessionState) -> Void)? { get set }
    var diagnostics: ScrcpyDiagnostics { get }
    var diagnosticsDidChange: ((ScrcpyDiagnostics) -> Void)? { get set }
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
    public private(set) var diagnostics = ScrcpyDiagnostics()
    public var diagnosticsDidChange: ((ScrcpyDiagnostics) -> Void)?

    private let scrcpyPath: String
    private let launcher: Launcher
    private let commandBuilder: ScrcpyCommandBuilder
    private let diagnosticLineLimit: Int
    private let logger = Logger(subsystem: "com.facundopri.airdroid.spike", category: "Mirroring")
    private var runningProcess: (any RunningProcess)?
    private var activeSessionID: UUID?
    private var stoppingSessionID: UUID?
    private var outputBuffers: [ScrcpyOutputChannel: String] = [:]

    public init(
        scrcpyPath: String,
        launcher: Launcher,
        commandBuilder: ScrcpyCommandBuilder = ScrcpyCommandBuilder(),
        diagnosticLineLimit: Int = 40
    ) {
        self.scrcpyPath = scrcpyPath
        self.launcher = launcher
        self.commandBuilder = commandBuilder
        self.diagnosticLineLimit = max(1, diagnosticLineLimit)
    }

    public func start(configuration: MirroringConfiguration) throws -> ScrcpyInvocation {
        guard runningProcess == nil else {
            throw ScrcpyMirroringEngineError.sessionAlreadyRunning
        }

        transition(to: .starting(configuration.device))
        stoppingSessionID = nil
        outputBuffers = [:]
        updateDiagnostics(ScrcpyDiagnostics())
        let invocation = commandBuilder.build(configuration: configuration)
        logger.info(
            "scrcpy start requested preset=\(configuration.preset.rawValue, privacy: .public) audio=\(configuration.audioEnabled, privacy: .public) recording=\(configuration.recordingURL != nil, privacy: .public)"
        )

        do {
            let sessionID = UUID()
            let process = try launcher.launch(
                executable: scrcpyPath,
                arguments: invocation.arguments
            ) { [weak self] output in
                Task { @MainActor [weak self] in
                    self?.handleOutput(sessionID: sessionID, output: output)
                }
            }
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
        stoppingSessionID = activeSessionID
        activeSessionID = nil
        runningProcess = nil
        if process.isRunning {
            process.terminate()
        }
        transition(to: .stopped)
        logger.info("scrcpy session stopped")
    }

    private func handleTermination(sessionID: UUID, status: Int32) {
        let wasActive = activeSessionID == sessionID
        let wasStopping = stoppingSessionID == sessionID
        guard wasActive || wasStopping else { return }

        flushOutputBuffers()
        updateDiagnostics(
            ScrcpyDiagnostics(
                recentLines: diagnostics.recentLines,
                lastExitStatus: status
            )
        )

        if wasActive {
            activeSessionID = nil
            runningProcess = nil
            transition(to: .failed("scrcpy stopped unexpectedly (exit \(status)). Reconnect to try again."))
            logger.error("scrcpy session ended unexpectedly exitStatus=\(status, privacy: .public)")
        } else {
            stoppingSessionID = nil
            logger.info("scrcpy child exited after stop exitStatus=\(status, privacy: .public)")
        }
    }

    private func handleOutput(sessionID: UUID, output: ScrcpyProcessOutput) {
        guard activeSessionID == sessionID || stoppingSessionID == sessionID else {
            return
        }

        let combined = outputBuffers[output.channel, default: ""] + output.text
        let components = combined.components(separatedBy: "\n")
        outputBuffers[output.channel] = components.last ?? ""
        for component in components.dropLast() {
            appendDiagnostic(channel: output.channel, message: component)
        }
    }

    private func flushOutputBuffers() {
        for channel in [ScrcpyOutputChannel.standardOutput, .standardError] {
            if let remainder = outputBuffers[channel], !remainder.isEmpty {
                appendDiagnostic(channel: channel, message: remainder)
            }
        }
        outputBuffers = [:]
    }

    private func appendDiagnostic(channel: ScrcpyOutputChannel, message: String) {
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMessage.isEmpty else { return }

        let line = ScrcpyDiagnosticLine(channel: channel, message: normalizedMessage)
        let lines = Array((diagnostics.recentLines + [line]).suffix(diagnosticLineLimit))
        updateDiagnostics(
            ScrcpyDiagnostics(
                recentLines: lines,
                lastExitStatus: diagnostics.lastExitStatus
            )
        )
    }

    private func updateDiagnostics(_ nextDiagnostics: ScrcpyDiagnostics) {
        diagnostics = nextDiagnostics
        diagnosticsDidChange?(nextDiagnostics)
    }

    private func transition(to nextState: MirroringSessionState) {
        state = nextState
        stateDidChange?(nextState)
    }
}

public final class FoundationRunningProcess: RunningProcess, @unchecked Sendable {
    private let process: Process
    private let stdout: Pipe
    private let stderr: Pipe
    private let outputHandler: @Sendable (ScrcpyProcessOutput) -> Void
    private let terminationLock = NSLock()
    private var terminationHandler: (@Sendable (Int32) -> Void)?
    private var pendingTerminationStatus: Int32?

    init(
        process: Process,
        stdout: Pipe,
        stderr: Pipe,
        outputHandler: @escaping @Sendable (ScrcpyProcessOutput) -> Void
    ) {
        self.process = process
        self.stdout = stdout
        self.stderr = stderr
        self.outputHandler = outputHandler
        process.terminationHandler = { [self] process in
            process.terminationHandler = nil
            handleTermination(status: process.terminationStatus)
        }
    }

    public var isRunning: Bool { process.isRunning }

    public func terminate() {
        process.terminate()
    }

    public func observeTermination(_ handler: @escaping @Sendable (Int32) -> Void) {
        terminationLock.lock()
        if let pendingTerminationStatus {
            self.pendingTerminationStatus = nil
            terminationLock.unlock()
            handler(pendingTerminationStatus)
        } else {
            terminationHandler = handler
            terminationLock.unlock()
        }
    }

    private func handleTermination(status: Int32) {
        drainRemainingOutput(from: stdout, channel: .standardOutput)
        drainRemainingOutput(from: stderr, channel: .standardError)

        terminationLock.lock()
        if let terminationHandler {
            self.terminationHandler = nil
            terminationLock.unlock()
            terminationHandler(status)
        } else {
            pendingTerminationStatus = status
            terminationLock.unlock()
        }
    }

    private func drainRemainingOutput(from pipe: Pipe, channel: ScrcpyOutputChannel) {
        pipe.fileHandleForReading.readabilityHandler = nil
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { return }
        outputHandler(
            ScrcpyProcessOutput(
                channel: channel,
                text: String(decoding: data, as: UTF8.self)
            )
        )
    }
}

public struct FoundationProcessLauncher: ProcessLaunching {
    public init() {}

    public func launch(
        executable: String,
        arguments: [String],
        outputHandler: @escaping @Sendable (ScrcpyProcessOutput) -> Void
    ) throws -> any RunningProcess {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputHandler(
                ScrcpyProcessOutput(
                    channel: .standardOutput,
                    text: String(decoding: data, as: UTF8.self)
                )
            )
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputHandler(
                ScrcpyProcessOutput(
                    channel: .standardError,
                    text: String(decoding: data, as: UTF8.self)
                )
            )
        }

        do {
            let runningProcess = FoundationRunningProcess(
                process: process,
                stdout: stdout,
                stderr: stderr,
                outputHandler: outputHandler
            )
            try process.run()
            return runningProcess
        } catch {
            process.terminationHandler = nil
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw error
        }
    }
}
