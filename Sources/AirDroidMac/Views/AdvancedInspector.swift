import AirDroidScrcpy
import SwiftUI

struct AdvancedInspector: View {
    @Bindable var store: ControlCenterStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Advanced Details", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Spacer()
                Button {
                    store.isAdvancedVisible = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Hide Advanced Details")
                .accessibilityLabel("Hide Advanced Details")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            Form {
                Section("Connection") {
                    LabeledContent("Selected serial", value: store.presentedEndpoint?.identity.serial ?? "None")
                    LabeledContent("Route", value: selectedRouteLabel)
                    LabeledContent("Provenance", value: selectedProvenanceLabel)
                    LabeledContent("State", value: store.sessionLabel)
                    LabeledContent(
                        "Last scrcpy exit",
                        value: store.diagnostics.lastExitStatus.map(String.init) ?? "Not available"
                    )
                }

                Section("Tools") {
                    LabeledContent("ADB", value: store.resolvedADBPath)
                    LabeledContent("scrcpy", value: store.resolvedScrcpyPath)
                }

                Section("Discovered ADB endpoints") {
                    if store.devices.isEmpty {
                        Text("No ADB endpoints are currently visible.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.devices) { device in
                            LabeledContent(
                                device.identity.displayName,
                                value: device.identity.serial
                            )
                            .textSelection(.enabled)
                        }
                    }
                }

                Section("Discovered Wireless Debugging endpoints") {
                    if store.wirelessConnectionCandidates.isEmpty,
                       store.pairingCandidates.isEmpty {
                        Text("No mDNS wireless endpoints are currently visible.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.wirelessConnectionCandidates) { candidate in
                            LabeledContent("Connect service", value: candidate.endpoint.adbAddress)
                                .textSelection(.enabled)
                        }
                        ForEach(store.pairingCandidates) { candidate in
                            LabeledContent("Pairing service", value: candidate.endpoint.adbAddress)
                                .textSelection(.enabled)
                        }
                    }
                }

                if let invocation = store.effectiveInvocation {
                    Section("Effective configuration") {
                        ForEach(invocation.arguments, id: \.self) { argument in
                            Text(argument)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section("Recent scrcpy output") {
                    if store.diagnostics.recentLines.isEmpty {
                        Text("No process output captured for this session yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(
                            Array(store.diagnostics.recentLines.enumerated()),
                            id: \.offset
                        ) { _, line in
                            Text("\(channelLabel(line.channel))  \(line.message)")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .inspectorColumnWidth(min: 260, ideal: 310)
    }

    private var selectedRouteLabel: String {
        switch store.presentedEndpoint?.route {
        case .directUSB: "Direct USB"
        case .secureWirelessDebugging: "Secure Wireless Debugging"
        case .legacyWirelessUntilRestart: "USB-assisted Wi-Fi until restart"
        case .unclassifiedWireless: "Unclassified wireless"
        case .emulator: "Emulator"
        case nil: "None"
        }
    }

    private var selectedProvenanceLabel: String {
        switch store.presentedEndpoint?.provenance {
        case .adbUSBObservation: "Observed by ADB over USB"
        case .secureServiceObservation: "Observed secure mDNS connection service"
        case .appInitiatedLegacyTransition: "Verified app-initiated USB transition"
        case .emulatorObservation: "Observed emulator"
        case .unverified: "Unverified"
        case nil: "None"
        }
    }

    private func channelLabel(_ channel: ScrcpyOutputChannel) -> String {
        switch channel {
        case .standardOutput: "OUT"
        case .standardError: "ERR"
        }
    }
}
