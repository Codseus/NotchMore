import Foundation

final class CapsLockNoDelayManager {
    static let shared = CapsLockNoDelayManager()

    private let enabledDelayOverride = 0
    private let defaultDelayOverride = -1

    private init() {}

    func updateState() {
        if UserDefaults.standard.bool(forKey: "enableCapsLockNoDelay") {
            setEnabled(true)
        }
    }

    func setEnabled(_ enabled: Bool) {
        let delay = enabled ? enabledDelayOverride : defaultDelayOverride
        guard setDelayOverride(milliseconds: delay) else {
            print("CapsLockNoDelayManager: failed to set CapsLockDelayOverride=\(delay)")
            return
        }
    }

    @discardableResult
    private func setDelayOverride(milliseconds: Int) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = [
            "property",
            "--set",
            "{\"CapsLockDelayOverride\":\(milliseconds)}",
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            print("CapsLockNoDelayManager: \(error)")
            return false
        }
    }
}
