public enum MirroringSessionState: Equatable, Sendable {
    case idle
    case starting(DeviceIdentity)
    case mirroring(DeviceIdentity)
    case stopped
    case failed(String)
}
