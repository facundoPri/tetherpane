import AirDroidDomain
import SwiftUI

struct DeviceSidebar: View {
    let devices: [DiscoveredDevice]
    let wirelessCandidates: [WirelessConnectionCandidate]
    @Binding var selection: DeviceSidebarSelection?

    var body: some View {
        List(selection: $selection) {
            Section("Devices") {
                if devices.isEmpty {
                    Label("No authorized devices", systemImage: "iphone.slash")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(devices) { device in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.identity.displayName)
                            Text(connectionLabel(for: device))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                            .tag(DeviceSidebarSelection.device(device.id))
                    }
                }
            }

            if !wirelessCandidates.isEmpty {
                Section("Nearby over Wi-Fi") {
                    ForEach(wirelessCandidates) { candidate in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Android device")
                            Text("Detected · pairing may be required")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(DeviceSidebarSelection.wirelessCandidate(candidate.id))
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        .navigationTitle("AirDroid")
    }

    private func connectionLabel(for device: DiscoveredDevice) -> String {
        switch device.state {
        case .authorized:
            switch device.transport {
            case .usb: "USB"
            case .wireless: wirelessConnectionLabel(for: device)
            case .emulator: "Emulator"
            case .unknown: "Authorized"
            }
        case .offline: "Offline"
        case .unauthorized: "Authorize on phone"
        case let .unknown(value): value
        }
    }

    private func wirelessConnectionLabel(for device: DiscoveredDevice) -> String {
        if device.identity.serial.hasSuffix(":5555") {
            "Wi-Fi · until restart"
        } else if device.identity.serial.contains("_adb-tls-connect._tcp") {
            "Wi-Fi · Wireless Debugging"
        } else {
            "Wi-Fi"
        }
    }
}
