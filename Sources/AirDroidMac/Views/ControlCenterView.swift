import AirDroidDomain
import SwiftUI

struct ControlCenterView: View {
    @Bindable var store: ControlCenterStore
    @State private var isWirelessSetupPresented = false
    @State private var wirelessSetupRoute: WirelessSetupRoute = .secure
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            DeviceSourceList(store: store)
                .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 310)
                .navigationTitle("TetherPane")
        } detail: {
            selectedDetail
        }
        .task {
            while !Task.isCancelled {
                store.refreshDevices(showProgress: false)
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .onChange(of: store.navigationSelection) {
            store.activateNavigationSelection()
        }
        .sheet(isPresented: $isWirelessSetupPresented) {
            WirelessSetupSheet(
                store: store,
                initialRoute: wirelessSetupRoute
            )
        }
        .inspector(isPresented: $store.isAdvancedVisible) {
            AdvancedInspector(store: store)
        }
    }

    @ViewBuilder
    private var selectedDetail: some View {
        switch store.navigationSelection {
        case .device:
            if let item = store.selectedDeviceItem {
                switch item.presence {
                case .connected, .authorizationRequired:
                    OneDeviceWorkspaceView(
                        store: store,
                        openWirelessSetup: { presentWirelessSetup(.secure) }
                    )
                    .navigationTitle(item.displayName)
                case .locallyDisconnected, .offline:
                    OfflineDeviceWorkspace(
                        item: item,
                        store: store,
                        openWirelessSetup: { presentWirelessSetup(.secure) }
                    )
                    .navigationTitle(item.displayName)
                }
            } else {
                USBCAutomaticWorkspace(store: store)
                    .navigationTitle("USB-C")
            }
        case .wifiOnly:
            WiFiOnlyWorkspace(
                store: store,
                openSecureSetup: { presentWirelessSetup(.secure) },
                openUSBAssistedSetup: { presentWirelessSetup(.usbAssisted) }
            )
            .navigationTitle("Wi-Fi Only")
        case .usbAutomatic, nil:
            USBCAutomaticWorkspace(store: store)
                .navigationTitle("USB-C")
        }
    }

    private func presentWirelessSetup(_ route: WirelessSetupRoute) {
        wirelessSetupRoute = route
        isWirelessSetupPresented = true
    }
}

private struct USBCAutomaticWorkspace: View {
    @Bindable var store: ControlCenterStore

    private var usbItems: [DeviceListItem] {
        store.connectedDeviceItems.filter { item in
            item.endpoints.contains(where: { $0.route == .directUSB })
        }
    }

    var body: some View {
        ConnectionChoiceCanvas(
            systemImage: "cable.connector",
            title: "USB-C connects automatically",
            subtitle: "Plug in a data-capable cable, unlock your phone, and approve USB debugging. TetherPane handles the rest."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if usbItems.isEmpty {
                    Label("Waiting for a USB-C phone", systemImage: "cable.connector")
                        .font(.headline)
                    Text("Your phone appears in Devices as soon as Android authorizes this Mac.")
                        .foregroundStyle(.secondary)
                } else {
                    Label(
                        usbItems.count == 1
                            ? "1 phone connected automatically"
                            : "\(usbItems.count) phones connected automatically",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(.green)
                    ForEach(usbItems) { item in
                        Button(item.displayName, systemImage: "iphone.gen2") {
                            store.navigationSelection = .device(item.id)
                        }
                    }
                }

                Divider()

                NumberedSetupStep(number: 1, text: "Connect your phone with USB-C.")
                NumberedSetupStep(number: 2, text: "Unlock it and tap Allow on the USB debugging prompt.")
                NumberedSetupStep(number: 3, text: "Select the phone under Devices and click Mirror.")
            }
        }
    }
}

private struct WiFiOnlyWorkspace: View {
    @Bindable var store: ControlCenterStore
    let openSecureSetup: () -> Void
    let openUSBAssistedSetup: () -> Void

    var body: some View {
        ConnectionChoiceCanvas(
            systemImage: "wifi",
            title: "Use your phone without a cable",
            subtitle: "Wireless Debugging is the recommended encrypted connection. Pair once, then reconnect while Android keeps it enabled."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                Label("Secure Wireless Debugging", systemImage: "lock.shield.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text("Android stays in control of the visible setting and pairing approval. No companion app is installed on your phone.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Button("Set Up Wireless Debugging…", action: openSecureSetup)
                        .buttonStyle(.borderedProminent)

                    if let usbDevice = store.selectedAuthorizedUSBDevice {
                        Button(
                            store.isOpeningDeveloperOptions
                                ? "Opening…"
                                : "Open Developer Options",
                            systemImage: "gearshape"
                        ) {
                            store.openDeveloperOptions(on: usbDevice)
                        }
                        .disabled(store.isOpeningDeveloperOptions)
                    }
                }

                Divider()

                DisclosureGroup("Use USB once (until restart)") {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Unencrypted on the local network", systemImage: "exclamationmark.shield")
                            .foregroundStyle(.orange)
                        Text("This optional shortcut uses an authorized USB phone to open classic ADB over Wi-Fi. It normally ends when the phone restarts and has a separate Turn Off action.")
                            .foregroundStyle(.secondary)
                        Button("Review USB-assisted Setup…", action: openUSBAssistedSetup)
                    }
                    .padding(.top, 10)
                }
            }
        }
    }
}

private struct OfflineDeviceWorkspace: View {
    let item: DeviceListItem
    @Bindable var store: ControlCenterStore
    let openWirelessSetup: () -> Void
    @State private var isForgetConfirmationPresented = false

    var body: some View {
        ConnectionChoiceCanvas(
            systemImage: "iphone.slash",
            title: item.displayName,
            subtitle: statusExplanation
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Label(statusTitle, systemImage: "circle.fill")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                if let candidate = store.reconnectCandidate(for: item) {
                    Button("Reconnect over Wi-Fi", systemImage: "wifi") {
                        store.connectWirelessly(candidate: candidate)
                    }
                    .buttonStyle(.borderedProminent)
                } else if isUSBRecord {
                    Label(
                        "Connect this phone with USB-C and it will reconnect automatically.",
                        systemImage: "cable.connector"
                    )
                    .foregroundStyle(.secondary)
                } else {
                    Button("Set Up Wireless Debugging…", action: openWirelessSetup)
                }

                if let message = store.deviceManagementMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if item.isSaved {
                    Divider()

                    Button("Forget from List…", role: .destructive) {
                        isForgetConfirmationPresented = true
                    }
                    .disabled(!store.canForget(item))
                    .help(store.canForget(item)
                        ? "Remove this offline device from TetherPane"
                        : "Wait until the exact ADB endpoint is no longer visible")

                    Text("Forgetting removes only this Mac's saved row. To revoke trust, remove this computer in Android's Wireless Debugging settings.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .confirmationDialog(
            "Forget \(item.displayName)?",
            isPresented: $isForgetConfirmationPresented
        ) {
            Button("Forget from List", role: .destructive) {
                store.forget(item)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved row from TetherPane. Android's Wireless Debugging authorization is unchanged.")
        }
    }

    private var isUSBRecord: Bool {
        if case .usb = item.id { return true }
        return false
    }

    private var statusTitle: String {
        if case .locallyDisconnected = item.presence {
            return "Disconnected on this Mac"
        }
        return "Offline"
    }

    private var statusExplanation: String {
        if !item.isSaved {
            return "This exact ADB endpoint is currently unavailable. Its physical phone identity, connection route, and authorization lifetime are not verified."
        }
        if case .locallyDisconnected = item.presence {
            return "The local ADB connection is closed. Android still remembers this Mac, so reconnecting usually does not require pairing again."
        }
        return "This saved device is not currently reachable. Its last connection remains visible so you can recognize and manage it."
    }
}

private struct ConnectionChoiceCanvas<Content: View>: View {
    let systemImage: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(
        systemImage: String,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top, spacing: 18) {
                    Image(systemName: systemImage)
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(.tint)
                        .frame(width: 48)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.largeTitle.weight(.semibold))
                        Text(subtitle)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                content
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
        }
    }
}
