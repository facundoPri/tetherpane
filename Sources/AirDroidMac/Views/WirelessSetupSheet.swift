import AirDroidDomain
import SwiftUI

enum WirelessSetupRoute: String, CaseIterable, Identifiable {
    case secure
    case usbAssisted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .secure: "Secure Wireless"
        case .usbAssisted: "Use USB Once"
        }
    }
}

struct WirelessSetupSheet: View {
    @Bindable var store: ControlCenterStore
    @Environment(\.dismiss) private var dismiss
    @State private var route: WirelessSetupRoute
    @State private var pairingCode = ""
    @State private var acceptsLegacyRisk = false

    init(
        store: ControlCenterStore,
        initialRoute: WirelessSetupRoute = .secure
    ) {
        self.store = store
        _route = State(initialValue: initialRoute)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Connection method", selection: $route) {
                        ForEach(WirelessSetupRoute.allCases) { route in
                            Text(route.label).tag(route)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text("Use your phone without a cable")
                } footer: {
                    Text("Secure Wireless is recommended. The USB-assisted option is faster to set up, but it is unencrypted and normally ends when the phone restarts.")
                }

                switch route {
                case .secure:
                    secureWirelessSections
                case .usbAssisted:
                    usbAssistedSections
                }
            }
            .formStyle(.grouped)
            .disabled(store.isCompletingLegacySetup)
            .navigationTitle("Wireless Setup")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 520, idealHeight: 620)
    }

    @ViewBuilder
    private var secureWirelessSections: some View {
        Section("Secure Wireless — Recommended") {
            Label("Encrypted by Android Wireless Debugging", systemImage: "lock.shield")
                .foregroundStyle(.green)
            Text("No cable or Android app is required. Android must visibly enable Wireless Debugging, approve this Wi-Fi network, and pair this Mac.")
                .foregroundStyle(.secondary)

            SetupInstruction(number: 1, text: "On Android, open Developer options → Wireless debugging.")
            SetupInstruction(number: 2, text: "Turn it on and approve the current Wi-Fi network.")
            SetupInstruction(number: 3, text: "Choose Pair device with pairing code and keep that dialog open.")

            if let usbDevice = store.selectedAuthorizedUSBDevice {
                Button(
                    store.isOpeningDeveloperOptions
                        ? "Opening Developer Options…"
                        : "Open Developer Options on phone",
                    systemImage: "gearshape"
                ) {
                    store.openDeveloperOptions(on: usbDevice)
                }
                .disabled(store.isOpeningDeveloperOptions)
            } else if store.requiresUSBDisambiguation {
                Label("Disconnect all but one same-name USB phone before opening Developer Options.", systemImage: "cable.connector")
                    .foregroundStyle(.orange)
            } else if store.distinctUSBDevices.filter({ $0.state == .authorized }).count > 1 {
                Label("Close this setup, select the USB phone under Devices, then reopen Wi-Fi Only.", systemImage: "iphone.gen2")
                    .foregroundStyle(.orange)
            }
        }

        Section("Nearby secure connections") {
            if store.wirelessConnectionCandidates.isEmpty {
                Label("Waiting for Wireless Debugging", systemImage: "wifi")
                    .foregroundStyle(.secondary)
                Text("Keep the Wireless debugging screen open. Discovery refreshes automatically.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(store.wirelessConnectionCandidates.enumerated()), id: \.element.id) { index, candidate in
                    Button(
                        store.wirelessConnectionCandidates.count == 1
                            ? "Connect Nearby Connection"
                            : "Connect Nearby Connection \(index + 1)",
                        systemImage: "wifi"
                    ) {
                        store.connectWirelessly(candidate: candidate)
                    }
                }
                Text("Nearby services are connection candidates, not proof of a physical phone identity. TetherPane keeps ambiguous connections separate.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let message = store.wirelessConnectionMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Pair with the code on Android") {
            if store.pairingCandidates.isEmpty {
                Label("Waiting for Android's pairing-code dialog", systemImage: "ellipsis")
                    .foregroundStyle(.secondary)
            } else {
                SecureField("Six-digit code", text: $pairingCode)
                    .textContentType(.oneTimeCode)
                    .accessibilityLabel("Six-digit pairing code shown by Android")

                ForEach(Array(store.pairingCandidates.enumerated()), id: \.element.id) { index, candidate in
                    Button(
                        store.pairingCandidates.count == 1
                            ? "Pair and Connect"
                            : "Pair Connection \(index + 1)",
                        systemImage: "lock.open"
                    ) {
                        store.pair(candidate: candidate, code: pairingCode)
                        pairingCode = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Text("The short-lived code stays only in memory. Android may later expire or revoke this Mac's authorization, in which case pairing is the recovery path.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let message = store.pairingMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var usbAssistedSections: some View {
        Section("USB-assisted Wi-Fi — Until Restart") {
            Label("Unencrypted local-network connection", systemImage: "exclamationmark.shield")
                .foregroundStyle(.orange)
            Text("TetherPane will use the currently authorized USB connection to open a classic ADB listener, verify the exact Wi-Fi endpoint, and tell you when the cable can be removed.")
                .foregroundStyle(.secondary)
            Text("The listener normally remains open until you turn it off or the phone restarts. Use this only on a trusted private network.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        Section("Safety confirmation") {
            Toggle(
                "I am on a trusted private network and understand this connection is unencrypted.",
                isOn: $acceptsLegacyRisk
            )
            .toggleStyle(.checkbox)

            if let usbDevice = store.selectedAuthorizedUSBDevice {
                Button("Enable Wi-Fi Until Restart", systemImage: "cable.connector.horizontal") {
                    store.connectOverTCPIP(from: usbDevice)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!acceptsLegacyRisk)
            } else if store.requiresUSBDisambiguation {
                Label("Disconnect all but one same-name USB phone before enabling this listener.", systemImage: "cable.connector")
                    .foregroundStyle(.orange)
            } else if store.distinctUSBDevices.filter({ $0.state == .authorized }).count > 1 {
                Label("Close this setup, select the USB phone under Devices, then reopen Wi-Fi Only.", systemImage: "iphone.gen2")
                    .foregroundStyle(.orange)
            } else if store.distinctUSBDevices.contains(where: { $0.state == .unauthorized }) {
                Label("Unlock your phone and tap Allow before continuing.", systemImage: "lock.open.display")
                    .foregroundStyle(.orange)
            } else {
                Label("Connect and authorize your phone over USB first.", systemImage: "cable.connector")
                    .foregroundStyle(.secondary)
            }

            if let message = store.wirelessConnectionMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SetupInstruction: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number, format: .number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(text)
        }
    }
}
