import AirDroidDomain
import SwiftUI

struct OneDeviceWorkspaceView: View {
    @Bindable var store: ControlCenterStore
    let openWirelessSetup: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch store.presentation.workspace {
                case .disconnected:
                    DisconnectedWorkspace(openWirelessSetup: openWirelessSetup)
                case let .usbDisambiguationRequired(candidateCount):
                    USBDisambiguationWorkspace(
                        candidateCount: candidateCount,
                        openWirelessSetup: openWirelessSetup
                    )
                case let .usbAuthorizationRequired(identity):
                    USBAuthorizationWorkspace(
                        identity: identity,
                        openWirelessSetup: openWirelessSetup
                    )
                case let .ready(endpoint):
                    ReadyWorkspace(
                        endpoint: endpoint,
                        store: store,
                        openWirelessSetup: openWirelessSetup
                    )
                case let .legacyEnabling(endpoint):
                    LegacyEnablingWorkspace(endpoint: endpoint, store: store)
                case let .legacySafeToUnplug(endpoint):
                    ReadyWorkspace(
                        endpoint: endpoint,
                        store: store,
                        openWirelessSetup: openWirelessSetup,
                        statusMessage: "Wi-Fi is verified. You can unplug the USB cable now."
                    )
                case let .secureWirelessNearby(candidateCount):
                    SecureNearbyWorkspace(
                        candidateCount: candidateCount,
                        openWirelessSetup: openWirelessSetup
                    )
                case let .securePairing(candidateCount):
                    SecurePairingWorkspace(
                        candidateCount: candidateCount,
                        openWirelessSetup: openWirelessSetup
                    )
                case let .mirroring(endpoint):
                    ReadyWorkspace(
                        endpoint: endpoint,
                        store: store,
                        openWirelessSetup: openWirelessSetup
                    )
                }

                if let notice = visibleNotice {
                    ConnectionNoticeView(
                        notice: notice,
                        store: store,
                        openWirelessSetup: openWirelessSetup
                    )
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 1),
            value: store.presentation.workspace
        )
    }

    private var visibleNotice: ConnectionNotice? {
        store.presentation.notice
    }
}

private struct USBDisambiguationWorkspace: View {
    let candidateCount: Int
    let openWirelessSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            WorkspaceHero(
                systemImage: "cable.connector",
                title: "Leave one phone connected",
                subtitle: "TetherPane sees \(candidateCount) USB endpoints with the same phone name. Disconnect all but the phone you want so the app does not invent a physical identity."
            )

            Label(
                "Raw endpoint serials remain available in Advanced for diagnostics.",
                systemImage: "info.circle"
            )
            .foregroundStyle(.secondary)

            Button("Use without a cable…", systemImage: "wifi", action: openWirelessSetup)
                .keyboardShortcut("w", modifiers: [.command, .option])
        }
    }
}

private struct DisconnectedWorkspace: View {
    let openWirelessSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            WorkspaceHero(
                systemImage: "cable.connector",
                title: "Connect your Android phone",
                subtitle: "USB is the fastest way to start. Connect a cable, unlock your phone, and approve USB debugging when Android asks."
            )

            WorkspaceCard("Start with USB") {
                VStack(alignment: .leading, spacing: 12) {
                    NumberedSetupStep(number: 1, text: "Connect your phone to this Mac with a data-capable USB cable.")
                    NumberedSetupStep(number: 2, text: "Unlock the phone and tap Allow on the USB debugging prompt.")
                    NumberedSetupStep(number: 3, text: "Your phone will appear here with one Mirror button.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("Use without a cable…", systemImage: "wifi", action: openWirelessSetup)
                .keyboardShortcut("w", modifiers: [.command, .option])
        }
    }
}

private struct USBAuthorizationWorkspace: View {
    let identity: DeviceIdentity
    let openWirelessSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            WorkspaceHero(
                systemImage: "lock.open.display",
                title: "Unlock your phone and tap Allow",
                subtitle: "\(identity.displayName) is connected over USB, but Android has not authorized this Mac yet. Keep the cable attached."
            )

            ConnectionBadge(label: "USB · Waiting for approval", systemImage: "cable.connector", color: .orange)

            WorkspaceCard("On your phone") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("1. Unlock the screen.")
                    Text("2. Find the USB debugging prompt.")
                    Text("3. Tap Allow. You may choose Always allow from this computer.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("Use without a cable…", systemImage: "wifi", action: openWirelessSetup)
                .keyboardShortcut("w", modifiers: [.command, .option])
        }
    }
}

private struct ReadyWorkspace: View {
    let endpoint: ADBEndpoint
    @Bindable var store: ControlCenterStore
    let openWirelessSetup: () -> Void
    var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    readyIdentity
                    Spacer(minLength: 16)
                    mirrorButton
                }

                VStack(alignment: .leading, spacing: 16) {
                    readyIdentity
                    mirrorButton
                }
            }

            if let statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Success. \(statusMessage)")
            }

            MirrorSettingsPanel(store: store)

            ConnectionStatusPanel(
                endpoint: endpoint,
                store: store,
                openWirelessSetup: openWirelessSetup
            )
        }
    }

    private var readyIdentity: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(endpoint.identity.displayName)
                .font(.largeTitle.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            ConnectionBadge(
                label: connectionPresentation.status,
                systemImage: connectionStyle.systemImage,
                color: connectionStyle.color
            )
        }
    }

    private var mirrorButton: some View {
        Button(mirrorActionLabel) {
            store.toggleMirroring(endpoint: endpoint)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(store.isStartingMirroring)
        .accessibilityHint(store.isMirroring
            ? "Stops the current stock scrcpy session"
            : "Starts stock scrcpy for this exact ADB endpoint")
    }

    private var connectionPresentation: ConnectionPanelPresentation {
        ConnectionPanelPresentation(route: endpoint.route)
    }

    private var mirrorActionLabel: String {
        if store.isStartingMirroring {
            return "Starting…"
        }
        return store.isMirroring ? "Stop Mirroring" : "Mirror"
    }

    private var connectionStyle: ConnectionRouteVisualStyle {
        ConnectionRouteVisualStyle(route: endpoint.route)
    }
}

private struct MirrorSettingsPanel: View {
    @Bindable var store: ControlCenterStore

    var body: some View {
        WorkspaceCard("Mirror settings") {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 18) {
                        qualityPicker
                            .frame(minWidth: 220)

                        Divider()
                            .frame(height: 38)

                        audioToggle

                        recordToggle
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        qualityPicker
                        Divider()
                        audioToggle
                        Divider()
                        recordToggle
                    }
                }

                Text("These settings apply when the next stock scrcpy session starts.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var qualityPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quality")
                .font(.callout.weight(.medium))
            Picker("Quality", selection: $store.selectedPreset) {
                ForEach(MirrorPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var audioToggle: some View {
        Toggle(isOn: $store.audioEnabled) {
            Label("Device audio", systemImage: "speaker.wave.2")
        }
    }

    private var recordToggle: some View {
        Toggle(isOn: $store.recordNextSession) {
            Label("Record next session", systemImage: "record.circle")
        }
    }
}

private struct ConnectionStatusPanel: View {
    let endpoint: ADBEndpoint
    @Bindable var store: ControlCenterStore
    let openWirelessSetup: () -> Void

    private var presentation: ConnectionPanelPresentation {
        ConnectionPanelPresentation(route: endpoint.route)
    }

    var body: some View {
        WorkspaceCard("Connection") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Label(presentation.title, systemImage: connectionStyle.systemImage)
                        .font(.headline)
                    Spacer(minLength: 12)
                    Text(presentation.status)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(connectionStyle.color)
                }

                LabeledContent("Security", value: presentation.security)

                Text(presentation.lifecycle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if hasManagementControls {
                    Divider()
                    managementControls
                }

                routeWarning
            }
        }
    }

    private var hasManagementControls: Bool {
        presentation.management != .none
    }

    @ViewBuilder
    private var managementControls: some View {
        switch presentation.management {
        case .unplugUSB:
            HStack(spacing: 12) {
                Button("Use without a cable…", systemImage: "wifi", action: openWirelessSetup)
                    .keyboardShortcut("w", modifiers: [.command, .option])

                if let device = store.presentedDevice,
                   store.hasPossibleLegacyRisk(for: device) {
                    Button("Turn Off Possible USB-assisted Wi-Fi", role: .destructive) {
                        store.disableTCPIP(on: device)
                    }
                }
            }
        case .disconnectOnThisMac:
            if let item = store.selectedDeviceItem {
                Button(
                    store.disconnectingDeviceID == item.id
                        ? "Disconnecting…"
                        : "Disconnect on This Mac",
                    role: .destructive
                ) {
                    store.disconnect(item)
                }
                .disabled(store.disconnectingDeviceID != nil)
            }
        case .disconnectUnverifiedEndpoint:
            if let item = store.selectedDeviceItem {
                Button(
                    store.disconnectingDeviceID == item.id
                        ? "Disconnecting…"
                        : "Disconnect Unverified Endpoint",
                    role: .destructive
                ) {
                    store.disconnect(item)
                }
                .disabled(store.disconnectingDeviceID != nil)
            }
        case .turnOffWirelessUntilRestart:
            if let device = store.presentedDevice {
                Button("Turn Off USB-assisted Wi-Fi", role: .destructive) {
                    store.disableTCPIP(on: device)
                }
            }
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var routeWarning: some View {
        if endpoint.route == .legacyWirelessUntilRestart {
            Label(
                "This route is unencrypted. Turn it off when you are finished.",
                systemImage: "exclamationmark.shield"
            )
            .font(.callout)
            .foregroundStyle(.orange)
        } else if endpoint.route == .unclassifiedWireless {
            Label(
                "TetherPane will not infer a physical device identity from this endpoint.",
                systemImage: "questionmark.diamond"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        } else if endpoint.route == .directUSB,
                  let device = store.presentedDevice,
                  store.hasPossibleLegacyRisk(for: device) {
            Label(
                "A prior USB-assisted setup may have opened an unencrypted listener. Use Turn Off before unplugging.",
                systemImage: "exclamationmark.shield"
            )
            .font(.callout)
            .foregroundStyle(.orange)
        }
    }

    private var connectionStyle: ConnectionRouteVisualStyle {
        ConnectionRouteVisualStyle(route: endpoint.route)
    }
}

private struct ConnectionRouteVisualStyle {
    let systemImage: String
    let color: Color

    init(route: ConnectionRoute) {
        switch route {
        case .directUSB:
            systemImage = "cable.connector"
            color = .green
        case .secureWirelessDebugging:
            systemImage = "wifi"
            color = .green
        case .legacyWirelessUntilRestart:
            systemImage = "wifi"
            color = .orange
        case .unclassifiedWireless:
            systemImage = "wifi"
            color = .secondary
        case .emulator:
            systemImage = "desktopcomputer"
            color = .secondary
        }
    }
}

private struct LegacyEnablingWorkspace: View {
    let endpoint: ADBEndpoint
    @Bindable var store: ControlCenterStore

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceHero(
                systemImage: "cable.connector.horizontal",
                title: "Keep the cable connected",
                subtitle: "TetherPane is enabling and verifying Wi-Fi for \(endpoint.identity.displayName). Do not unplug until this screen says it is safe."
            )
            ProgressView("Enabling Wi-Fi until the phone restarts…")
                .accessibilityLabel("Enabling and verifying USB-assisted Wi-Fi")

            if let device = store.presentedDevice {
                Button("Turn Off USB-assisted Wi-Fi", role: .destructive) {
                    store.disableTCPIP(on: device)
                }
                .disabled(!store.canTurnOffLegacyRisk)
            }
        }
    }
}

private struct SecureNearbyWorkspace: View {
    let candidateCount: Int
    let openWirelessSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceHero(
                systemImage: "wifi",
                title: "Wireless Debugging is nearby",
                subtitle: candidateCount == 1
                    ? "A secure Android connection is visible, but its physical phone identity is not verified yet."
                    : "Multiple secure Android connections are visible. TetherPane will keep them separate until Android proves which one you authorize."
            )
            Button("Continue Wireless Setup…", action: openWirelessSetup)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("w", modifiers: [.command, .option])
        }
    }
}

private struct SecurePairingWorkspace: View {
    let candidateCount: Int
    let openWirelessSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceHero(
                systemImage: "lock.badge.clock",
                title: "Pairing code ready",
                subtitle: "Android is exposing a short-lived secure pairing window. Enter the six-digit code while that system dialog remains open."
            )
            Button("Enter Pairing Code…", action: openWirelessSetup)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("w", modifiers: [.command, .option])
                .accessibilityHint("Opens the secure Wireless Debugging setup sheet")
        }
    }
}

private struct WorkspaceHero: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
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
    }
}

private struct WorkspaceCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            content
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct ConnectionBadge: View {
    let label: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.callout.weight(.medium))
            .foregroundStyle(color)
    }
}

private struct ConnectionNoticeView: View {
    let notice: ConnectionNotice
    @Bindable var store: ControlCenterStore
    let openWirelessSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(notice.message, systemImage: style.image)
                .font(.callout)
                .foregroundStyle(style.color)
                .fixedSize(horizontal: false, vertical: true)

            if let recovery = notice.recovery {
                Button(recovery.buttonLabel, action: { perform(recovery) })
                    .controlSize(.small)
            }
        }
    }

    private var style: (image: String, color: Color) {
        switch notice.kind {
        case .progress: ("hourglass", .secondary)
        case .success: ("checkmark.circle", .green)
        case .warning: ("exclamationmark.triangle", .orange)
        case .failure: ("xmark.octagon", .red)
        }
    }

    private func perform(_ recovery: ConnectionRecoveryAction) {
        switch recovery {
        case .refresh:
            store.refreshDevices()
        case .retryWirelessSetup:
            openWirelessSetup()
        case .reconnectMirror:
            store.reconnect()
        }
    }
}
