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

    var settingsURL: URL? {
        let pane: String
        switch self {
        case .accessibility:
            pane = "Privacy_Accessibility"
        case .inputMonitoring:
            pane = "Privacy_InputMonitoring"
        case .screenRecording:
            pane = "Privacy_ScreenRecording"
        }

        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
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
                return IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
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
        guard let url = permission.settingsURL else { return }
        NSWorkspace.shared.open(url)
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
