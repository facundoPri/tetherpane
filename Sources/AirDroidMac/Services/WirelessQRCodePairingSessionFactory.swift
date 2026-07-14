import AirDroidDomain

enum WirelessQRCodePairingSessionFactory {
    static func make() -> WirelessQRCodePairingSession {
        WirelessQRCodePairingSession(
            serviceName: "studio-\(randomString(length: 10, alphabet: serviceAlphabet))",
            password: randomString(length: 10, alphabet: passwordAlphabet)
        )
    }

    private static let serviceAlphabet = Array(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    )
    private static let passwordAlphabet = Array("0123456789")

    private static func randomString(length: Int, alphabet: [Character]) -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in
            alphabet.randomElement(using: &generator)!
        })
    }
}
