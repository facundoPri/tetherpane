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

            Section("Pair with code — recommended") {
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

            Section("QR pairing — Android system scanner only") {
                if let session = store.qrPairingSession {
                    HStack(alignment: .top, spacing: 24) {
                        WirelessQRCodeView(payload: session.payload)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("On the phone:")
                                .font(.headline)
                            Text("1. Open Settings → System → Developer options → Wireless debugging.")
                            Text("2. Choose Pair device with QR code.")
                            Text("3. Scan this code. AirDroid will detect, pair, and select the Wi-Fi device automatically.")
                            Text("Do not use the regular Camera app or the AirDroid companion: they cannot authorize ADB and may interpret this as a Wi-Fi network.")
                                .font(.callout)
                                .foregroundStyle(.orange)
                            Text("Keep this screen open while pairing. No USB cable is required.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Button("Cancel QR pairing", role: .cancel) {
                                store.cancelQRCodePairing()
                            }
                        }
                    }
                } else {
                    Text("Use this only from Android's built-in Wireless Debugging → Pair device with QR code scanner. A normal camera sees the shared WIFI envelope and may try to join a network instead.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Generate system-scanner QR code", systemImage: "qrcode") {
                        store.beginQRCodePairing(for: candidate)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Wi-Fi device")
        .task(id: store.qrPairingSession?.id) {
            while store.qrPairingSession != nil, !Task.isCancelled {
                store.continueQRCodePairing()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var matchingPairingCandidates: [PairingCandidate] {
        store.pairingCandidates.filter { pairingCandidate in
            pairingCandidate.host == candidate.host
        }
    }
}
