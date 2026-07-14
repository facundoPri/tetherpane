import SwiftUI

struct AdvancedInspector: View {
    @Bindable var store: ControlCenterStore

    var body: some View {
        Form {
            Section("Connection") {
                LabeledContent("Selected serial", value: store.selectedDevice?.identity.serial ?? "None")
                LabeledContent("Transport", value: selectedTransportLabel)
                LabeledContent("State", value: store.sessionLabel)
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
}
