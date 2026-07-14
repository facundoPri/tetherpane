public protocol PairingClient {
    /// Pairs one mDNS-discovered Wireless Debugging endpoint using a code the caller keeps only in memory.
    func pair(candidate: PairingCandidate, code: String) throws
}
