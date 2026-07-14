import AirDroidScrcpy
import SwiftUI

struct AdvancedInspector: View {
    @Bindable var store: ControlCenterStore

    var body: some View {
        Form {
            Section("Connection") {
                LabeledContent("Selected serial", value: store.selectedDevice?.identity.serial ?? "None")
                LabeledContent("Transport", value: selectedTransportLabel)
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

            PairingGuidanceView(store: store)

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
        .padding()
        .inspectorColumnWidth(min: 260, ideal: 310)
    }

    private var selectedTransportLabel: String {
        switch store.selectedDevice?.transport {
        case .usb: "USB"
        case .wireless: "Wi-Fi"
        case .emulator: "Emulator"
        case .unknown: "Unknown"
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
