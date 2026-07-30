import AppKit
import Foundation

@MainActor
final class DesktopCleanerManager: ObservableObject {
    static let shared = DesktopCleanerManager()

    @Published private(set) var isDesktopClean: Bool

    private static let finderBundleIdentifier = "com.apple.finder" as CFString
    private static let createDesktopKey = "CreateDesktop" as CFString
    private static let originalCreateDesktopKey = "desktopCleanerOriginalCreateDesktop"

    private init() {
        isDesktopClean = Self.currentCreateDesktopValue() == false
    }

    func toggle() {
        isDesktopClean ? showDesktopIcons() : hideDesktopIcons()
    }

    private func hideDesktopIcons() {
        if UserDefaults.standard.string(forKey: Self.originalCreateDesktopKey) == nil {
            let original = Self.currentCreateDesktopValue()
            UserDefaults.standard.set(
                original.map { $0 ? "true" : "false" } ?? "unset",
                forKey: Self.originalCreateDesktopKey
            )
        }

        Self.setCreateDesktopValue(false)
        isDesktopClean = true
        Self.restartFinder()
    }

    private func showDesktopIcons() {
        let original = UserDefaults.standard.string(forKey: Self.originalCreateDesktopKey)

        switch original {
        case "false":
            Self.setCreateDesktopValue(false)
        case "true":
            Self.setCreateDesktopValue(true)
        default:
            Self.removeCreateDesktopValue()
        }

        UserDefaults.standard.removeObject(forKey: Self.originalCreateDesktopKey)
        isDesktopClean = false
        Self.restartFinder()
    }

    private static func currentCreateDesktopValue() -> Bool? {
        CFPreferencesAppSynchronize(finderBundleIdentifier)
        return CFPreferencesCopyAppValue(createDesktopKey, finderBundleIdentifier) as? Bool
    }

    private static func setCreateDesktopValue(_ value: Bool) {
        CFPreferencesSetAppValue(createDesktopKey, value as CFBoolean, finderBundleIdentifier)
        CFPreferencesAppSynchronize(finderBundleIdentifier)
    }

    private static func removeCreateDesktopValue() {
        CFPreferencesSetAppValue(createDesktopKey, nil, finderBundleIdentifier)
        CFPreferencesAppSynchronize(finderBundleIdentifier)
    }

    private static func restartFinder() {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = ["Finder"]
            try? process.run()
            process.waitUntilExit()
        }
    }
}
