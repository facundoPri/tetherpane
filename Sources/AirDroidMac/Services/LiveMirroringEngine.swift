import AirDroidDomain
import AirDroidScrcpy
import Foundation

@MainActor
enum LiveMirroringEngine {
    static func make() -> any MirroringEngine {
        guard let scrcpyPath = DeveloperToolPathResolver.scrcpyPath() else {
            return UnavailableMirroringEngine(message: "scrcpy 4.1 is not installed. Run make doctor and set SCRCPY_PATH if needed.")
        }
        return ScrcpyMirroringEngine(scrcpyPath: scrcpyPath, launcher: FoundationProcessLauncher())
    }
}

@MainActor
private final class UnavailableMirroringEngine: MirroringEngine {
    private let message: String
    private(set) var state: MirroringSessionState = .idle
    var stateDidChange: ((MirroringSessionState) -> Void)?

    init(message: String) {
        self.message = message
    }

    func start(configuration: MirroringConfiguration) throws -> ScrcpyInvocation {
        transition(to: .failed(message))
        throw MirroringUnavailableError(message: message)
    }

    func stop() {
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
