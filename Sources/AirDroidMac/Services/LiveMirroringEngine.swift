import AirDroidDomain
import AirDroidScrcpy
import Foundation
import TetherPaneUIFixtureSupport

@MainActor
enum LiveMirroringEngine {
    static func make() -> any MirroringEngine {
        if UIFixture.active != nil {
            return UIFixtureMirroringEngine()
        }
        guard let scrcpyPath = DeveloperToolPathResolver.scrcpyPath() else {
            return UnavailableMirroringEngine(
                message: DeveloperToolInstallationGuidance.scrcpyUnavailable
            )
        }
        return ScrcpyMirroringEngine(scrcpyPath: scrcpyPath, launcher: FoundationProcessLauncher())
    }
}

@MainActor
private final class UIFixtureMirroringEngine: MirroringEngine {
    private(set) var state: MirroringSessionState = .idle
    var stateDidChange: ((MirroringSessionState) -> Void)?
    private(set) var diagnostics = ScrcpyDiagnostics()
    var diagnosticsDidChange: ((ScrcpyDiagnostics) -> Void)?

    func start(configuration: MirroringConfiguration) async throws -> ScrcpyInvocation {
        let message = UIFixtureActionError().localizedDescription
        state = .failed(message)
        stateDidChange?(state)
        throw UIFixtureActionError()
    }

    func stop() async {
        state = .stopped
        stateDidChange?(state)
    }
}

@MainActor
private final class UnavailableMirroringEngine: MirroringEngine {
    private let message: String
    private(set) var state: MirroringSessionState = .idle
    var stateDidChange: ((MirroringSessionState) -> Void)?
    private(set) var diagnostics = ScrcpyDiagnostics()
    var diagnosticsDidChange: ((ScrcpyDiagnostics) -> Void)?

    init(message: String) {
        self.message = message
    }

    func start(configuration: MirroringConfiguration) async throws -> ScrcpyInvocation {
        transition(to: .failed(message))
        throw MirroringUnavailableError(message: message)
    }

    func stop() async {
        transition(to: .stopped)
    }

    private func transition(to nextState: MirroringSessionState) {
        state = nextState
        stateDidChange?(nextState)
    }
}

private struct MirroringUnavailableError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
