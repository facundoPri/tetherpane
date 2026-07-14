import AirDroidDomain
import SwiftUI

struct PairingGuidanceView: View {
    @Bindable var store: ControlCenterStore
    @State private var pairingCode = ""

    var body: some View {
        Section("Wireless Debugging") {
            if store.wirelessConnectionCandidates.isEmpty {
                Text("No Wi-Fi connection service is visible yet. Turn on Wireless Debugging and keep its screen open; discovery refreshes automatically.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.wirelessConnectionCandidates) { candidate in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Wi-Fi connection available")
                            .font(.headline)
                        Text("\(candidate.host):\(candidate.port)")
                            .font(.caption)
                            .textSelection(.enabled)
                        Button("Connect this endpoint", systemImage: "wifi") {
                            store.connectWirelessly(candidate: candidate)
                        }
                    }
                }
            }

            if let message = store.wirelessConnectionMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if store.pairingCandidates.isEmpty {
                Text("For first-time setup, choose Pair device with pairing code on the phone and keep that system dialog open. The six-digit field appears here automatically.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.pairingCandidates) { candidate in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(candidate.serviceName)
                            .font(.headline)
                        Text("\(candidate.host):\(candidate.port)")
                            .font(.caption)
                            .textSelection(.enabled)
                        SecureField("Six-digit code shown on the phone", text: $pairingCode)
                        Button("Pair and connect over Wi-Fi") {
                            store.pair(candidate: candidate, code: pairingCode)
                            pairingCode = ""
                        }
                        .disabled(pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            if let message = store.pairingMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
