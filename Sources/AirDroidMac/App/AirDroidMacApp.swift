import AppKit
import SwiftUI
import TetherPaneUIFixtureSupport

@main
struct TetherPaneApp: App {
    @NSApplicationDelegateAdaptor(AppActivationDelegate.self) private var appActivationDelegate
    @State private var store = ControlCenterStore(
        discovery: LiveDeviceDiscovery.make(),
        pairing: LivePairingClient.make(),
        wirelessConnection: LiveWirelessConnectionClient.make(),
        mirroring: LiveMirroringEngine.make(),
        uiFixture: UIFixture.active,
        legacyRiskStore: LegacyRiskStoreFactory.make(for: UIFixture.active),
        deviceDirectoryStore: DeviceDirectoryStoreFactory.make(for: UIFixture.active)
    )

    var body: some Scene {
        WindowGroup("TetherPane", id: "control-center") {
            ControlCenterView(store: store)
                .modifier(
                    UIFixturePresentationModifier(
                        profile: uiFixturePresentationProfile
                    )
                )
        }
        .defaultSize(width: 980, height: 640)

        Settings {
            SettingsView()
        }

        .commands {
            CommandMenu("Session") {
                Button("Refresh Connections") {
                    store.refreshDevices()
                }
                .keyboardShortcut("r")

                Divider()

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
                .keyboardShortcut("m", modifiers: [.command, .option])
                .disabled(!store.canMirrorSelectedDevice)

                Button("Reconnect Selected Device") {
                    store.reconnect()
                }
                .keyboardShortcut("m", modifiers: [.command, .option, .shift])
                .disabled(store.selectedAuthorizedEndpoint == nil)

                Button("Stop Mirroring") {
                    store.stopMirroring()
                }
                .keyboardShortcut(".")
                .disabled(!store.isMirroring)
            }
        }
    }

    private var uiFixturePresentationProfile: UIFixturePresentationProfile {
        UIFixturePresentationProfile(
            environment: ProcessInfo.processInfo.environment
        )
    }
}

private struct UIFixturePresentationModifier: ViewModifier {
    let profile: UIFixturePresentationProfile

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(profile.appearance.colorScheme)
            .environment(\.uiFixturePresentationProfile, profile)
    }
}

private extension UIFixturePresentationProfile.Appearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

private final class AppActivationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
