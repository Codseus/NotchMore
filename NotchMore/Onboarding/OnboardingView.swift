import AppKit
import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @AppStorage("enableClipboardHistory") private var enableClipboardHistory = true
    @AppStorage("enableFileShelf") private var enableFileShelf = true
    @AppStorage("enableWindowSwitcher") private var enableWindowSwitcher = false
    @AppStorage("enableDockPreviews") private var enableDockPreviews = false
    @AppStorage("enablePasteWithoutFormatting") private var enablePasteWithoutFormatting = false
    @AppStorage("enableCtrlXCutPaste") private var enableCtrlXCutPaste = false
    @AppStorage("enableCapsLockNoDelay") private var enableCapsLockNoDelay = false
    @AppStorage("enableThreeFingerMiddleClick") private var enableThreeFingerMiddleClick = false
    @AppStorage("invertMouseScroll") private var invertMouseScroll = false
    @AppStorage("invertTrackpadScroll") private var invertTrackpadScroll = false
    @AppStorage("enableRestEyes") private var enableRestEyes = false
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    @State private var permissionRefreshID = UUID()

    private var selectedPermissions: [AppPermission] {
        var permissions: [AppPermission] = []

        if enableWindowSwitcher {
            permissions += [.accessibility, .inputMonitoring, .screenRecording]
        }
        if enableDockPreviews {
            permissions += [.accessibility, .screenRecording]
        }
        if enablePasteWithoutFormatting || enableCtrlXCutPaste {
            permissions += [.accessibility, .inputMonitoring]
        }
        if enableThreeFingerMiddleClick || invertMouseScroll || invertTrackpadScroll {
            permissions.append(.accessibility)
        }

        return unique(permissions)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    OnboardingSection(title: "Notch") {
                        FeaturePickerRow(
                            icon: "rectangle.topthird.inset.filled",
                            title: "Clipboard History",
                            description: "Keep recent copied text and images in the notch.",
                            permissions: [],
                            isOn: $enableClipboardHistory,
                            permissionRefreshID: $permissionRefreshID
                        )
                        FeaturePickerRow(
                            icon: "tray.full",
                            title: "File Shelf",
                            description: "Drop files on the notch for quick temporary access.",
                            permissions: [],
                            isOn: $enableFileShelf,
                            permissionRefreshID: $permissionRefreshID
                        )
                    }

                    OnboardingSection(title: "Windows") {
                        FeaturePickerRow(
                            icon: "rectangle.3.group",
                            title: "Window Switcher",
                            description: "Switch between windows with live previews.",
                            permissions: [.accessibility, .inputMonitoring, .screenRecording],
                            isOn: $enableWindowSwitcher,
                            permissionRefreshID: $permissionRefreshID
                        )
                        FeaturePickerRow(
                            icon: "dock.rectangle",
                            title: "Dock Previews",
                            description: "Hover Dock apps to preview and activate windows.",
                            permissions: [.accessibility, .screenRecording],
                            isOn: $enableDockPreviews,
                            permissionRefreshID: $permissionRefreshID
                        )
                    }

                    OnboardingSection(title: "Keyboard And Finder") {
                        FeaturePickerRow(
                            icon: "textformat",
                            title: "Paste Plain Text",
                            description: "Strip formatting automatically when pasting.",
                            permissions: [.accessibility, .inputMonitoring],
                            isOn: $enablePasteWithoutFormatting,
                            permissionRefreshID: $permissionRefreshID
                        )
                        FeaturePickerRow(
                            icon: "scissors",
                            title: "Cut And Move Files",
                            description: "Use Cmd-X and Cmd-V to move Finder files.",
                            permissions: [.accessibility, .inputMonitoring],
                            isOn: $enableCtrlXCutPaste,
                            permissionRefreshID: $permissionRefreshID
                        )
                        FeaturePickerRow(
                            icon: "capslock",
                            title: "Caps Lock No Delay",
                            description: "Make Caps Lock respond immediately.",
                            permissions: [],
                            isOn: $enableCapsLockNoDelay,
                            permissionRefreshID: $permissionRefreshID
                        )
                    }

                    OnboardingSection(title: "Mouse And Trackpad") {
                        FeaturePickerRow(
                            icon: "hand.tap",
                            title: "Three-Finger Middle Click",
                            description: "Trigger middle click with a physical three-finger press.",
                            permissions: [.accessibility],
                            isOn: $enableThreeFingerMiddleClick,
                            permissionRefreshID: $permissionRefreshID
                        )
                        FeaturePickerRow(
                            icon: "scroll",
                            title: "Invert Mouse Scroll",
                            description: "Reverse mouse wheel direction only.",
                            permissions: [.accessibility],
                            isOn: $invertMouseScroll,
                            permissionRefreshID: $permissionRefreshID
                        )
                        FeaturePickerRow(
                            icon: "rectangle.and.hand.point.up.left",
                            title: "Invert Trackpad Scroll",
                            description: "Reverse trackpad scroll direction only.",
                            permissions: [.accessibility],
                            isOn: $invertTrackpadScroll,
                            permissionRefreshID: $permissionRefreshID
                        )
                    }

                    OnboardingSection(title: "General") {
                        FeaturePickerRow(
                            icon: "eye",
                            title: "Rest Eyes",
                            description: "Get periodic reminders to look away and rest.",
                            permissions: [],
                            isOn: $enableRestEyes,
                            permissionRefreshID: $permissionRefreshID
                        )
                        FeaturePickerRow(
                            icon: "menubar.rectangle",
                            title: "Menu Bar Icon",
                            description: "Keep quick access to Settings in the menu bar.",
                            permissions: [],
                            isOn: $showMenuBarIcon,
                            permissionRefreshID: $permissionRefreshID
                        )
                        FeaturePickerRow(
                            icon: "power",
                            title: "Launch At Login",
                            description: "Start NotchMore automatically when you sign in.",
                            permissions: [],
                            isOn: $launchAtLogin,
                            permissionRefreshID: $permissionRefreshID
                        )
                    }
                }
                .padding(22)
            }

            footer
        }
        .frame(minWidth: 760, minHeight: 680)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text("Set Up NotchMore")
                    .font(.system(size: 24, weight: .semibold))
                Text("Choose the tools you want now. You can change everything later in Settings.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(.regularMaterial)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            PermissionSummary(permissions: selectedPermissions, refreshID: permissionRefreshID)

            Spacer()

            Button("Request Permissions") {
                PermissionManager.request(selectedPermissions)
                schedulePermissionRefresh()
            }
            .disabled(selectedPermissions.isEmpty)

            Button("Finish") {
                PermissionManager.request(selectedPermissions)
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding_v1")
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore_v1")
                onFinish()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.regularMaterial)
    }

    private func schedulePermissionRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            permissionRefreshID = UUID()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            permissionRefreshID = UUID()
        }
    }

    private func unique(_ permissions: [AppPermission]) -> [AppPermission] {
        var seen = Set<AppPermission>()
        return permissions.filter { seen.insert($0).inserted }
    }
}

private struct OnboardingSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

private struct FeaturePickerRow: View {
    let icon: String
    let title: String
    let description: String
    let permissions: [AppPermission]
    @Binding var isOn: Bool
    @Binding var permissionRefreshID: UUID

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.accentColor)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    permissionBadges
                }

                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Toggle("", isOn: $isOn)
                .toggleStyle(SettingsPillToggleStyle())
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .onChange(of: isOn) { _, enabled in
            if enabled {
                requestPermissionsIfNeeded()
            }
        }
        .id(permissionRefreshID)
    }

    @ViewBuilder
    private var permissionBadges: some View {
        ForEach(permissions) { permission in
            let granted = PermissionManager.isGranted(permission)
            Button {
                if granted {
                    PermissionManager.openSettings(for: permission)
                } else {
                    _ = PermissionManager.request(permission)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        permissionRefreshID = UUID()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.system(size: 9, weight: .semibold))
                    Text(permission.title)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(granted ? .green : .orange)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill((granted ? Color.green : Color.orange).opacity(0.12))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func requestPermissionsIfNeeded() {
        guard isOn else { return }
        PermissionManager.request(permissions)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            permissionRefreshID = UUID()
        }
    }
}

private struct PermissionSummary: View {
    let permissions: [AppPermission]
    let refreshID: UUID

    var body: some View {
        HStack(spacing: 8) {
            if permissions.isEmpty {
                Label("No extra permissions needed", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                ForEach(permissions) { permission in
                    let granted = PermissionManager.isGranted(permission)
                    Label(permission.title, systemImage: granted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(granted ? .green : .secondary)
                }
            }
        }
        .font(.system(size: 11, weight: .medium))
        .id(refreshID)
    }
}
