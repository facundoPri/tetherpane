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

            Section("Wi-Fi mirroring") {
                if device.transport == .wireless {
                    Label("Connected over Wi-Fi", systemImage: "wifi")
                        .foregroundStyle(.green)
                    Text("The cable is not needed while this ADB Wi-Fi connection remains available.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if device.identity.serial.hasSuffix(":5555") {
                        Label("This classic ADB TCP/IP listener is not encrypted.", systemImage: "exclamationmark.shield")
                            .font(.callout)
                            .foregroundStyle(.orange)
                        Button("Turn off USB-assisted Wi-Fi", role: .destructive) {
                            store.disableTCPIP(on: device)
                        }
                    }
                } else if device.transport == .usb {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Wireless Debugging", systemImage: "wifi")
                            .font(.headline)
                        Text("Recommended for a remembered connection. Open Developer Options on the phone, turn on Wireless debugging, then choose Pair device with pairing code. Android does not allow the Mac to toggle or approve this setting silently.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Open Developer Options on phone", systemImage: "gearshape") {
                            store.openDeveloperOptions(on: device)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Use USB once", systemImage: "cable.connector")
                            .font(.headline)
                        Text("This switches the selected phone to classic ADB over TCP/IP on the local network. You can unplug the cable after it connects, but you must repeat this step after the phone restarts.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Label("Use only on a trusted private network; classic ADB TCP/IP traffic is not encrypted.", systemImage: "exclamationmark.shield")
                            .font(.callout)
                            .foregroundStyle(.orange)
                        Button("Enable Wi-Fi until phone restarts", systemImage: "bolt.horizontal.circle") {
                            store.connectOverTCPIP(from: device)
                        }
                        .buttonStyle(.borderedProminent)
                    }
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
                    Text("Turn on Wireless Debugging on the phone and keep both devices on the same Wi-Fi network. The nearby Wi-Fi row appears automatically.")
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
            case .wireless:
                if device.identity.serial.hasSuffix(":5555") {
                    "Authorized via Wi-Fi until restart"
                } else if device.identity.serial.contains("_adb-tls-connect._tcp") {
                    "Authorized via Wireless Debugging"
                } else {
                    "Authorized via Wi-Fi"
                }
            case .emulator: "Authorized emulator"
            case .unknown: "Authorized"
            }
        case .offline: "Offline"
        case .unauthorized: "Authorize on phone"
        case let .unknown(value): value
        }
    }
}
