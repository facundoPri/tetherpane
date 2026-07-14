import AirDroidDomain
import SwiftUI

struct ControlCenterView: View {
    @Bindable var store: ControlCenterStore

    var body: some View {
        NavigationSplitView {
            DeviceSidebar(
                devices: store.devices,
                wirelessCandidates: store.visibleWirelessConnectionCandidates,
                selection: $store.sidebarSelection
            )
        } detail: {
            if let device = store.selectedDevice {
                DeviceDetailView(device: device, store: store)
            } else if let candidate = store.selectedWirelessCandidate {
                WirelessCandidateDetailView(candidate: candidate, store: store)
            } else {
                NoDeviceDetailView(store: store)
            }
        }
        .task {
            while !Task.isCancelled {
                store.refreshDevices()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh devices", systemImage: "arrow.clockwise") {
                    store.refreshDevices()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Toggle("Advanced", isOn: $store.isAdvancedVisible)
            }
        }
        .inspector(isPresented: $store.isAdvancedVisible) {
            AdvancedInspector(store: store)
        }
    }
}

private struct NoDeviceDetailView: View {
    @Bindable var store: ControlCenterStore

    var body: some View {
        Form {
            Section("Wireless Debugging — no cable") {
                Label("Waiting for Android Wireless Debugging", systemImage: "wifi")
                Text("1. Put the phone and Mac on the same Wi-Fi network.")
                Text("2. On Android, enable Developer options → Wireless debugging.")
                Text("3. Choose Pair device with pairing code. This screen refreshes automatically and will show the code field.")
                Text("Android must show and approve the system pairing. No Android companion app is required.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let message = store.discoveryMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section("USB once — until restart") {
                Label("Connect and authorize the phone over USB", systemImage: "cable.connector")
                Text("Select the USB device in the sidebar, then choose Enable Wi-Fi until phone restarts. Once the Wi-Fi device appears, the cable can be removed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            PairingGuidanceView(store: store)
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Set up Wi-Fi mirroring")
    }
}
