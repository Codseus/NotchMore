import AppKit
import Foundation
import Sparkle

@MainActor
final class UpdateManager: NSObject, ObservableObject, @preconcurrency SPUStandardUserDriverDelegate {
    static let shared = UpdateManager()

    @Published private(set) var canCheckForUpdates = false

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: self
    )
    private var canCheckObservation: NSKeyValueObservation?

    private override init() {
        super.init()

        canCheckObservation = updaterController.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            Task { @MainActor in
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updaterController.checkForUpdates(sender)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }
}
