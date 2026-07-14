import AirDroidDomain
import SwiftUI

struct WirelessCandidateDetailView: View {
    let candidate: WirelessConnectionCandidate
    @Bindable var store: ControlCenterStore
    @State private var pairingCode = ""

    var body: some View {
        Form {
            Section("Nearby Android device") {
                Label("Detected over Wi-Fi", systemImage: "wifi")
                Text("This device is advertising Wireless Debugging. It must be paired with this Mac before scrcpy can mirror it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button("Connect if already paired", systemImage: "link") {
                    store.connectWirelessly(candidate: candidate)
                }

                if let message = store.wirelessConnectionMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Pair with code") {
                Text("On the phone, open Wireless Debugging and choose Pair device with pairing code. Keep that system dialog open; this Mac checks for it automatically.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if matchingPairingCandidates.isEmpty {
                    Label("Waiting for the phone's six-digit pairing dialog", systemImage: "ellipsis")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(matchingPairingCandidates) { pairingCandidate in
                        VStack(alignment: .leading, spacing: 8) {
                            SecureField("Six-digit code shown on the phone", text: $pairingCode)
                            Button("Pair and connect over Wi-Fi", systemImage: "wifi") {
                                store.pair(candidate: pairingCandidate, code: pairingCode)
                                pairingCode = ""
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                        }
                    }
                }

                Text("No USB cable is required. The pairing code is short-lived and stays only in memory.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let message = store.pairingMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Wi-Fi device")
    }

    private var matchingPairingCandidates: [PairingCandidate] {
        store.pairingCandidates.filter { pairingCandidate in
            pairingCandidate.host == candidate.host
        }
    }
}
