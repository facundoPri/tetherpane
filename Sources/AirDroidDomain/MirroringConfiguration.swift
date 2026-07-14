import Foundation

public enum MirrorPreset: String, CaseIterable, Identifiable, Sendable {
    case responsive
    case highQuality

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .responsive: "Responsive"
        case .highQuality: "High Quality"
        }
    }
}

public struct MirroringConfiguration: Equatable, Sendable {
    public let device: DeviceIdentity
    public let preset: MirrorPreset
    public let audioEnabled: Bool
    public let recordingURL: URL?

    public init(
        device: DeviceIdentity,
        preset: MirrorPreset,
        audioEnabled: Bool,
        recordingURL: URL?
    ) {
        self.device = device
        self.preset = preset
        self.audioEnabled = audioEnabled
        self.recordingURL = recordingURL
    }
}
