import AirDroidDomain
import SwiftUI

struct DeviceDetailView: View {
    let device: DiscoveredDevice
    @Bindable var store: ControlCenterStore

    var body: some View {
        Form {
            Section("Session") {
                LabeledContent("Device", value: device.identity.displayName)
                LabeledContent("Connection", value: connectionLabel)
                Picker("Preset", selection: $store.selectedPreset) {
                    ForEach(MirrorPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                Toggle("Forward device audio", isOn: $store.audioEnabled)
                Toggle("Record next session", isOn: $store.recordNextSession)
            }

            Section("Wireless") {
                if device.transport == .wireless {
                    Label("Connected over Wi-Fi", systemImage: "wifi")
                        .foregroundStyle(.green)
                } else if store.wirelessConnectionCandidates.count == 1,
                          let candidate = store.wirelessConnectionCandidates.first {
                    Text("Wireless Debugging is visible. Connect if this Mac was paired before, or select the nearby Wi-Fi row to pair with a six-digit code.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Connect if already paired", systemImage: "wifi") {
                        store.connectWirelessly(candidate: candidate)
                    }
                } else if store.wirelessConnectionCandidates.count > 1 {
                    Text("Multiple wireless devices are available. Open Advanced to choose the intended endpoint.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Turn on Wireless Debugging on the phone and keep both devices on the same Wi-Fi network. The nearby Wi-Fi row appears automatically; no cable is required.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let message = store.wirelessConnectionMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button(store.isMirroring ? "Stop Mirroring" : "Mirror") {
                    store.toggleMirroring()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("m")
                .disabled(device.state != .authorized)

                Button("Reconnect") {
                    store.reconnect()
                }
                .disabled(device.state != .authorized)
            }

            if let message = store.sessionMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle(device.identity.displayName)
    }

    private var connectionLabel: String {
        switch device.state {
        case .authorized:
            switch device.transport {
            case .usb: "Authorized via USB"
            case .wireless: "Authorized via Wi-Fi"
            case .emulator: "Authorized emulator"
            case .unknown: "Authorized"
            }
        case .offline: "Offline"
        case .unauthorized: "Authorize on phone"
        case let .unknown(value): value
        }
    }
}
