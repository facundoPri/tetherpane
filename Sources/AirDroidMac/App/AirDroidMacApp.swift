import AppKit
import SwiftUI

@main
struct AirDroidMacApp: App {
    @NSApplicationDelegateAdaptor(AppActivationDelegate.self) private var appActivationDelegate
    @State private var store = ControlCenterStore(
        discovery: LiveDeviceDiscovery.make(),
        pairing: LivePairingClient.make(),
        wirelessConnection: LiveWirelessConnectionClient.make(),
        mirroring: LiveMirroringEngine.make()
    )

    var body: some Scene {
        WindowGroup("AirDroid", id: "control-center") {
            ControlCenterView(store: store)
        }
        .defaultSize(width: 980, height: 640)

        Settings {
            SettingsView()
        }

        .commands {
            CommandMenu("Session") {
                Button("Use Responsive Preset") {
                    store.selectedPreset = .responsive
                }
                .keyboardShortcut("1", modifiers: [.command, .option])

                Button("Use High Quality Preset") {
                    store.selectedPreset = .highQuality
                }
                .keyboardShortcut("2", modifiers: [.command, .option])

                Button("Toggle Device Audio") {
                    store.audioEnabled.toggle()
                }
                .keyboardShortcut("a", modifiers: [.command, .option])

                Button("Toggle Record Next Session") {
                    store.recordNextSession.toggle()
                }
                .keyboardShortcut("r", modifiers: [.command, .option])

                Button("Toggle Advanced Inspector") {
                    store.isAdvancedVisible.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])

                Button("Mirror Selected Device") {
                    store.toggleMirroring()
                }
                .keyboardShortcut("m")
                .disabled(store.selectedDevice?.state != .authorized)

                Button("Reconnect Selected Device") {
                    store.reconnect()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(store.selectedDevice?.state != .authorized)

                Button("Stop Mirroring") {
                    store.stopMirroring()
                }
                .keyboardShortcut(".")
                .disabled(!store.isMirroring)
            }
        }
    }
}

private final class AppActivationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
