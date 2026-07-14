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
            Section("Cable-free setup") {
                Label("Waiting for Android Wireless Debugging", systemImage: "wifi")
                Text("1. Put the phone and Mac on the same Wi-Fi network.")
                Text("2. On Android, enable Developer options → Wireless debugging.")
                Text("3. Choose Pair device with pairing code. This screen refreshes automatically and will show the code field.")
                Text("You may unplug USB before starting. Same Wi-Fi carries the connection; Android's one-time system pairing authorizes ADB for scrcpy.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let message = store.discoveryMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            PairingGuidanceView(store: store)
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Set up Wi-Fi mirroring")
    }
}
