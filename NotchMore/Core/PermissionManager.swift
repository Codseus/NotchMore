import ApplicationServices
import AppKit
import CoreGraphics
import Foundation
import IOKit.hid

enum AppPermission: String, CaseIterable, Identifiable {
    case accessibility
    case inputMonitoring
    case screenRecording

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .inputMonitoring: return "Input Monitoring"
        case .screenRecording: return "Screen Recording"
        }
    }

    var settingsURLs: [URL] {
        let panes: [String]
        switch self {
        case .accessibility:
            panes = ["Privacy_Accessibility"]
        case .inputMonitoring:
            panes = [
                "Privacy_ListenEvent",
                "Privacy_InputMonitoring",
            ]
        case .screenRecording:
            panes = ["Privacy_ScreenCapture", "Privacy_ScreenRecording"]
        }

        return panes.compactMap {
            URL(string: "x-apple.systempreferences:com.apple.preference.security?\($0)")
        }
    }
}

enum PermissionManager {
    static func isGranted(_ permission: AppPermission) -> Bool {
        switch permission {
        case .accessibility:
            return accessibilityTrusted(prompt: false)
        case .inputMonitoring:
            return canCreateKeyboardEventTap()
        case .screenRecording:
            return CGPreflightScreenCaptureAccess()
        }
    }

    @discardableResult
    static func request(_ permission: AppPermission) -> Bool {
        switch permission {
        case .accessibility:
            return accessibilityTrusted(prompt: true)
        case .inputMonitoring:
            if #available(macOS 10.15, *) {
                let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
                if !granted {
                    openSettings(for: permission)
                }
                return granted
            }
            openSettings(for: permission)
            return false
        case .screenRecording:
            return CGRequestScreenCaptureAccess()
        }
    }

    static func request(_ permissions: [AppPermission]) {
        for permission in unique(permissions) where !isGranted(permission) {
            _ = request(permission)
        }
    }

    static func openSettings(for permission: AppPermission) {
        openFirstAvailableSettingsURL(permission.settingsURLs)
    }

    private static func openFirstAvailableSettingsURL(_ urls: [URL], index: Int = 0) {
        guard urls.indices.contains(index) else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(urls[index], configuration: configuration) { _, error in
            if error != nil {
                openFirstAvailableSettingsURL(urls, index: index + 1)
            }
        }
    }

    private static func accessibilityTrusted(prompt: Bool) -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func canCreateKeyboardEventTap() -> Bool {
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

    private static func unique(_ permissions: [AppPermission]) -> [AppPermission] {
        var seen = Set<AppPermission>()
        return permissions.filter { seen.insert($0).inserted }
    }
}
