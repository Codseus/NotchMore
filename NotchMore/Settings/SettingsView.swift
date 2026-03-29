import AppKit
import SwiftUI

// MARK: - Reusable Settings Components

struct SettingsCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.primary)
                .tracking(0.2)

            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct SettingsPillToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(configuration.isOn ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 42, height: 24)
                    .overlay(
                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                            .padding(2)
                            .offset(x: configuration.isOn ? 9 : -9)
                            .animation(.easeInOut(duration: 0.16), value: configuration.isOn)
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

struct SettingsToggleRow: View {
    let title: String?
    let subtitle: String?
    @Binding var isOn: Bool

    init(title: String? = nil, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if let title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(SettingsPillToggleStyle())
        }
    }
}

// MARK: - General Settings View

struct GeneralSettingsView: View {
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("hoverDelay") private var hoverDelay = 0.0
    // Permissions state
    @State private var accessibilityGranted: Bool = GeneralSettingsView.currentAccessibilityTrust()
    @State private var inputMonitoringGranted: Bool =
        GeneralSettingsView.canCreateInputMonitoringTap()
    @State private var screenRecordingGranted: Bool = CGPreflightScreenCaptureAccess()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsCard(title: "General") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsToggleRow(title: "Show Menu Bar Icon", isOn: $showMenuBarIcon)
                        SettingsToggleRow(title: "Launch at Login", isOn: $launchAtLogin)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Hover Delay")
                                    .font(.system(size: 13, weight: .medium))
                                Spacer()
                                Text(String(format: "%.1fs", hoverDelay))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $hoverDelay, in: 0...1, step: 0.1)
                        }
                    }
                }

                // Permissions Card (Accessibility, Input Monitoring, Screen Recording)
                SettingsCard(title: "Permissions") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Accessibility")
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Text(accessibilityGranted ? "Granted" : "Not Granted")
                                        .font(.caption)
                                        .foregroundColor(accessibilityGranted ? .green : .secondary)
                                }
                                Text(
                                    "Required for window switching, app control, and other Accessibility APIs."
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }

                            Button("Open Settings") {
                                if let url = URL(
                                    string:
                                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                                ) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Input Monitoring")
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Text(inputMonitoringGranted ? "Granted" : "Not Granted")
                                        .font(.caption)
                                        .foregroundColor(
                                            inputMonitoringGranted ? .green : .secondary)
                                }
                                Text(
                                    "Required to observe low-level keyboard input for Window Switcher (Command/Option+Tab)."
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }

                            Button("Open Settings") {
                                if let url = URL(
                                    string:
                                        "x-apple.systempreferences:com.apple.preference.security?Privacy_InputMonitoring"
                                ) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Screen Recording")
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Text(screenRecordingGranted ? "Granted" : "Not Granted")
                                        .font(.caption)
                                        .foregroundColor(
                                            screenRecordingGranted ? .green : .secondary)
                                }
                                Text(
                                    "Required for window thumbnails and ScreenCaptureKit snapshots."
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }

                            Button("Open Settings") {
                                if let url = URL(
                                    string:
                                        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenRecording"
                                ) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        HStack {
                            Button("Refresh") {
                                accessibilityGranted = Self.currentAccessibilityTrust()
                                inputMonitoringGranted = Self.canCreateInputMonitoringTap()
                                screenRecordingGranted = CGPreflightScreenCaptureAccess()
                            }
                            Spacer()
                        }

                        Text(
                            "Some permission changes may require quitting and reopening NotchMore before status updates."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func currentAccessibilityTrust() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func canCreateInputMonitoringTap() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue)
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: CGEventMask(mask),
                callback: { _, _, event, _ in Unmanaged.passRetained(event) },
                userInfo: nil
            )
        else {
            return false
        }

        CFMachPortInvalidate(tap)
        return true
    }
}

struct FunctionsSettingsView: View {
    @AppStorage("enableCtrlXCutPaste") private var enableCtrlXCutPaste = false
    @AppStorage("enableClipboardHistory") private var enableClipboardHistory = false
    @AppStorage("clipboardHistoryLimit") private var clipboardHistoryLimit = 10
    @AppStorage("enablePasteWithoutFormatting") private var enablePasteWithoutFormatting = false
    @AppStorage("enableThreeFingerMiddleClick") private var enableThreeFingerMiddleClick = false
    @AppStorage("invertMouseScroll") private var invertMouseScroll = false
    @AppStorage("invertTrackpadScroll") private var invertTrackpadScroll = false
    @AppStorage("enableWindowSwitcher") private var enableWindowSwitcher = false
    @AppStorage("enableFileShelf") private var enableFileShelf = false
    @AppStorage("windowSwitcherUseCommandTab") private var useCommandTab = false
    @AppStorage("enableRestEyes") private var enableRestEyes = false
    @AppStorage("restIntervalMinutes") private var restIntervalMinutes = 20
    @AppStorage("restDurationSeconds") private var restDurationSeconds = 20

    private let clipboardLimitOptions = [10, 20, 30, 40, 50]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsCard(title: "Notch Features") {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsToggleRow(
                            title: "Clipboard History",
                            subtitle: "Keep recent copied items in the notch.",
                            isOn: $enableClipboardHistory
                        )

                        Picker("History Size", selection: $clipboardHistoryLimit) {
                            ForEach(clipboardLimitOptions, id: \.self) { value in
                                Text("\(value) items").tag(value)
                            }
                        }
                        .pickerStyle(.menu)

                        Text(
                            "Track up to \(clipboardHistoryLimit) recent clipboard items with pin support"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    Divider()
                        .padding(.vertical, 8)
                    SettingsToggleRow(
                        title: "File Shelf",
                        subtitle: "Quick access shelf for files dropped on the notch.",
                        isOn: $enableFileShelf
                    )
                }
                SettingsCard(title: "3-Finger Click as Middle Click") {
                    SettingsToggleRow(
                        subtitle: "Triggers middle click on physical 3-finger press.",
                        isOn: $enableThreeFingerMiddleClick
                    )
                }

                SettingsCard(title: "Cut & Move Files with ⌘X") {
                    SettingsToggleRow(
                        subtitle: "Use ⌘X to cut files and ⌘V to move them.",
                        isOn: $enableCtrlXCutPaste
                    )
                }

                SettingsCard(title: "Window Switcher") {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsToggleRow(
                            subtitle: "Switch windows with live previews like Alt+Tab.",
                            isOn: $enableWindowSwitcher
                        )

                        if enableWindowSwitcher {
                            Picker("Keyboard Shortcut", selection: $useCommandTab) {
                                Text("⌥ Tab (Option + Tab)").tag(false)
                                Text("⌘ Tab (Replace System)").tag(true)
                            }
                            .pickerStyle(.radioGroup)

                            if useCommandTab {
                                Text("This will replace the system Command+Tab switcher")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }

                SettingsCard(title: "Paste without Formatting") {
                    SettingsToggleRow(
                        subtitle: "Automatically strips formatting when pasting with ⌘V.",
                        isOn: $enablePasteWithoutFormatting
                    )
                }

                SettingsCard(title: "Rest Eyes") {
                    SettingsToggleRow(
                        title: "Enable Rest Eyes",
                        subtitle: "Get reminded to take breaks to reduce eye strain.",
                        isOn: $enableRestEyes
                    )
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Break every")
                            Spacer()
                            Text("\(restIntervalMinutes) min")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Stepper("", value: $restIntervalMinutes, in: 5...120, step: 5)
                                .labelsHidden()
                        }

                        HStack {
                            Text("Break duration")
                            Spacer()
                            Text("\(restDurationSeconds) sec")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Stepper("", value: $restDurationSeconds, in: 10...300, step: 10)
                                .labelsHidden()
                        }

                        Text("You will get a notification 10 seconds before the break starts.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                SettingsCard(title: "Scroll") {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsToggleRow(title: "Invert Mouse Scroll", isOn: $invertMouseScroll)
                        SettingsToggleRow(
                            title: "Invert Trackpad Scroll", isOn: $invertTrackpadScroll)
                        Text("Requires Accessibility permissions.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
        }
        .onAppear {
            if !clipboardLimitOptions.contains(clipboardHistoryLimit) {
                clipboardHistoryLimit = 10
            }
        }
        .onChange(of: clipboardHistoryLimit) { _, value in
            if !clipboardLimitOptions.contains(value) {
                clipboardHistoryLimit = 10
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SettingsView: View {
    enum Panel: String, CaseIterable, Identifiable {
        case general = "General"
        case functions = "Functions"
        case info = "Info"
        var id: String { self.rawValue }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .functions: return "slider.horizontal.3"
            case .info: return "info.circle"
            }
        }

        var title: String {
            switch self {
            case .general: return "General"
            case .functions: return "Features"
            case .info: return "Info"
            }
        }
    }

    @State private var selectedPanel: Panel = .general

    init(initialPanel: Panel = .general) {
        _selectedPanel = State(initialValue: initialPanel)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                ForEach(Panel.allCases) { panel in
                    Button {
                        selectedPanel = panel
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: panel.icon)
                                .font(.system(size: 13, weight: .semibold))
                            Text(panel.title)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(selectedPanel == panel ? .white : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(selectedPanel == panel ? Color.accentColor : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(
                                    selectedPanel == panel
                                        ? Color.accentColor.opacity(0.95)
                                        : Color.primary.opacity(0.22),
                                    lineWidth: 1
                                )
                        )
                        .contentShape(Rectangle())
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.8))
            )

            Group {
                switch selectedPanel {
                case .general:
                    GeneralSettingsView()
                case .functions:
                    FunctionsSettingsView()
                case .info:
                    InfoView()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(NSColor.windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .clipped()
        }
        .padding(14)
        .frame(width: 700, height: 520)
        .background(
            LinearGradient(
                colors: [
                    Color(NSColor.windowBackgroundColor),
                    Color(NSColor.controlBackgroundColor).opacity(0.9),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

struct InfoView: View {
    @ObservedObject private var updateManager = UpdateManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            Text("NotchMore")
                .font(.title)
                .fontWeight(.bold)

            Text(
                "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")"
            )
            .font(.subheadline)
            .foregroundColor(.secondary)

            Divider()
                .padding(.horizontal)

            if updateManager.isChecking {
                ProgressView("Checking for updates...")
            } else {
                if updateManager.isUpdateAvailable {
                    VStack(spacing: 10) {
                        Text("A new version is available: \(updateManager.latestVersion)")
                            .font(.headline)
                            .foregroundColor(.green)

                        Text(updateManager.releaseNotes)
                            .font(.caption)
                            .lineLimit(3)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button("Download Update") {
                            updateManager.downloadUpdate()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack(spacing: 10) {
                        Text("You're up to date!")
                            .foregroundColor(.secondary)

                        if let error = updateManager.errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                        }

                        Button("Check for Updates") {
                            updateManager.checkForUpdates(manual: true)
                        }
                    }
                }
            }

            Spacer()

            Text("© 2026 Codseus")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
