import AirDroidDomain
import SwiftUI

struct DeviceSourceList: View {
    @Bindable var store: ControlCenterStore

    var body: some View {
        List(selection: $store.navigationSelection) {
            Section("Devices") {
                if store.connectedDeviceItems.isEmpty {
                    Label("No devices connected", systemImage: "iphone.slash")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.connectedDeviceItems) { item in
                        DeviceSourceRow(item: item)
                            .tag(ControlCenterNavigationSelection.device(item.id))
                    }
                }
            }

            if !store.offlineDeviceItems.isEmpty {
                Section("Offline") {
                    ForEach(store.offlineDeviceItems) { item in
                        DeviceSourceRow(item: item)
                            .tag(ControlCenterNavigationSelection.device(item.id))
                    }
                }
            }

            Section("Connect") {
                ConnectionSourceRow(
                    title: "USB-C",
                    subtitle: "Automatic",
                    systemImage: "cable.connector"
                )
                .tag(ControlCenterNavigationSelection.usbAutomatic)

                ConnectionSourceRow(
                    title: "Wi-Fi Only",
                    subtitle: "Wireless Debugging",
                    systemImage: "wifi"
                )
                .tag(ControlCenterNavigationSelection.wifiOnly)
            }

            Section("Utilities") {
                Button {
                    store.refreshDevices()
                } label: {
                    ConnectionSourceRow(
                        title: "Refresh Connections",
                        subtitle: "Scan USB and Wi-Fi",
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(.plain)
                .help("Refresh Android connections")

                Button {
                    store.isAdvancedVisible.toggle()
                } label: {
                    ConnectionSourceRow(
                        title: store.isAdvancedVisible
                            ? "Hide Advanced Details"
                            : "Advanced Details",
                        subtitle: "Endpoints and scrcpy",
                        systemImage: "slider.horizontal.3"
                    )
                }
                .buttonStyle(.plain)
                .help(store.isAdvancedVisible
                    ? "Hide connection and scrcpy details"
                    : "Show connection and scrcpy details")
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Devices and connection methods")
    }
}

private struct DeviceSourceRow: View {
    let item: DeviceListItem

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "iphone.gen2")
                    .font(.title3)
                    .frame(width: 24)
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(.background, lineWidth: 1.5))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .lineLimit(1)
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var statusLabel: String {
        switch item.presence {
        case let .connected(route):
            switch route {
            case .usbC: "USB-C · Connected"
            case .secureWiFi: "Wi-Fi · Connected"
            case .legacyWiFiUntilRestart: "Wi-Fi until restart"
            case .emulator: "Emulator · Connected"
            case .unverifiedWiFi: "Wi-Fi · Route unverified"
            }
        case .authorizationRequired:
            "USB-C · Tap Allow on phone"
        case .locallyDisconnected:
            "Disconnected on this Mac"
        case let .offline(lastRoute):
            switch lastRoute {
            case .usbC: "Offline · Last used USB-C"
            case .secureWiFi: "Offline · Last used Wi-Fi"
            case .legacyWiFiUntilRestart: "Offline · Wi-Fi ended"
            case .emulator: "Offline · Emulator"
            case .unverifiedWiFi: "Offline · Wi-Fi route unknown"
            }
        }
    }

    private var statusColor: Color {
        switch item.presence {
        case .connected: .green
        case .authorizationRequired: .orange
        case .locallyDisconnected, .offline: .secondary
        }
    }
}

private struct ConnectionSourceRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .frame(width: 24)
        }
        .padding(.vertical, 2)
    }
}
