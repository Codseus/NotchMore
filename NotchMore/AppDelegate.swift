import AppKit
import Combine
import CoreGraphics
import ServiceManagement
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var restWarningWindow: NSWindow?
    var restBlockingWindow: NSWindow?
    var statusItem: NSStatusItem?
    var globalKeyMonitor: Any?
    var settingsWindow: NSWindow?
    var onboardingWindow: NSWindow?

    private var mediaManager = MediaManager()
    private var clipboardManager = ClipboardManager()
    private var pasteManager = PasteManager()
    private var fileCutPasteManager = FileCutPasteManager()
    private var fileShelfManager = FileShelfManager()
    private var restManager = RestManager()
    private var threeFingerClickManager = ThreeFingerClickManager.shared

    private var cancellables = Set<AnyCancellable>()

    @AppStorage("enablePasteWithoutFormatting") private var enablePasteWithoutFormatting: Bool =
        false
    @AppStorage("enableCtrlXCutPaste") private var enableCtrlXCutPaste: Bool = false
    @AppStorage("enableClipboardHistory") private var enableClipboardHistory: Bool = false
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon: Bool = true
    @AppStorage("enableFileShelf") private var enableFileShelf: Bool = false
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("invertMouseScroll") private var invertMouseScroll: Bool = false
    @AppStorage("invertTrackpadScroll") private var invertTrackpadScroll: Bool = false
    @AppStorage("hoverDelay") private var hoverDelay: Double = 0.0
    @AppStorage("enableWindowSwitcher") private var enableWindowSwitcher: Bool = false
    @AppStorage("enableDockPreviews") private var enableDockPreviews: Bool = false
    var windowSwitcherWindow: NSWindow?
    var dockPreviewWindow: NSWindow?
    var permissionsWindow: NSWindow?
    private var lastWindowSwitcherIDs: [CGWindowID] = []
    private var notchPanelController: NotchPanelController?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupAppMenu()
        setupWindows()
        setupWindowSwitcherWindow()
        setupDockPreviewWindow()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        updateClipboardMonitoring()
        updatePasteMonitoring()
        updateFileCutPasteMonitoring()
        updateMenuBarIcon()

        ScrollManager.shared.updateSettings()
        ThreeFingerClickManager.shared.updateMonitoringState()
        CapsLockNoDelayManager.shared.updateState()
        SystemHUDManager.shared.start()

        setupRestWindows()
        _ = UpdateManager.shared

        if enableWindowSwitcher {
            WindowSwitcherManager.shared.start()
        }
        if enableDockPreviews {
            DockPreviewManager.shared.start()
        }

        setupCombineObservers()

        let hasCompletedOnboarding = UserDefaults.standard.bool(
            forKey: "hasCompletedOnboarding_v1")
        if !hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.openOnboarding()
            }
        }
    }

    // MARK: - App Menu Setup

    private func setupAppMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()

        let settingsItem = NSMenuItem(
            title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)

        let updateItem = NSMenuItem(
            title: "Check for Updates...", action: #selector(UpdateManager.checkForUpdates(_:)),
            keyEquivalent: "")
        updateItem.target = UpdateManager.shared
        appMenu.addItem(updateItem)

        appMenu.addItem(NSMenuItem.separator())

        let hideItem = NSMenuItem(
            title: "Hide NotchMore", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(hideItem)

        let hideOthersItem = NSMenuItem(
            title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)

        appMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit NotchMore", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Window Setup

    private func setupWindowSwitcherWindow() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.alphaValue = 0
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.acceptsMouseMovedEvents = true

        let hostingView = NSHostingView(rootView: WindowSwitcherView())
        window.contentView = hostingView

        window.center()

        self.windowSwitcherWindow = window
    }

    private func layoutWindowSwitcherWindow(_ window: NSWindow) {
        let size = CGSize(
            width: WindowSwitcherLayout.width(
                forWindowCount: max(1, WindowSwitcherManager.shared.windows.count)
            ),
            height: WindowSwitcherLayout.height(
                forWindowCount: max(1, WindowSwitcherManager.shared.windows.count)
            )
        )
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = (screenFrame.width - size.width) / 2
        let y = (screenFrame.height - size.height) / 2
        setFrameIfNeeded(
            NSRect(x: x, y: y, width: size.width, height: size.height),
            for: window
        )
    }

    private func setupDockPreviewWindow() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.alphaValue = 0
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.acceptsMouseMovedEvents = true

        window.contentView = NSHostingView(rootView: DockPreviewView())
        self.dockPreviewWindow = window
    }

    private func layoutDockPreviewWindow(_ window: NSWindow) {
        let visibleCount = DockPreviewManager.shared.windows.isEmpty
            ? 1
            : DockPreviewManager.shared.windows.count
        let maxWidth = (NSScreen.main?.visibleFrame.width ?? 1200) * 0.9
        let size = CGSize(
            width: min(DockPreviewLayout.width(forWindowCount: visibleCount), maxWidth),
            height: DockPreviewLayout.height
        )
        let anchorFrame = DockPreviewManager.shared.anchorFrame
        let anchor = anchorFrame.isEmpty
            ? DockPreviewManager.shared.anchorPoint
            : CGPoint(x: anchorFrame.midX, y: anchorFrame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let fullScreenFrame = screen?.frame ?? screenFrame
        let edgePadding: CGFloat = 12
        let gap: CGFloat = 10

        let isLeftDock = anchorFrame.isEmpty
            ? anchor.x < screenFrame.minX + 96
            : anchorFrame.midX < fullScreenFrame.minX + 96
        let isRightDock = anchorFrame.isEmpty
            ? anchor.x > screenFrame.maxX - 96
            : anchorFrame.midX > fullScreenFrame.maxX - 96

        let x: CGFloat
        let y: CGFloat
        if isLeftDock {
            let itemMaxX = anchorFrame.isEmpty ? anchor.x : anchorFrame.maxX
            x = min(screenFrame.maxX - size.width - edgePadding, itemMaxX + gap)
            y = min(max(screenFrame.minY + edgePadding, anchor.y - size.height / 2), screenFrame.maxY - size.height - edgePadding)
        } else if isRightDock {
            let itemMinX = anchorFrame.isEmpty ? anchor.x : anchorFrame.minX
            x = max(screenFrame.minX + edgePadding, itemMinX - size.width - gap)
            y = min(max(screenFrame.minY + edgePadding, anchor.y - size.height / 2), screenFrame.maxY - size.height - edgePadding)
        } else {
            let itemMaxY = anchorFrame.isEmpty ? anchor.y : anchorFrame.maxY
            x = min(max(screenFrame.minX + edgePadding, anchor.x - size.width / 2), screenFrame.maxX - size.width - edgePadding)
            y = min(
                max(screenFrame.minY + edgePadding, itemMaxY + gap),
                screenFrame.maxY - size.height - edgePadding
            )
        }

        let frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        setFrameIfNeeded(frame, for: window)
        DockPreviewManager.shared.setPreviewWindowFrame(frame)
    }

    private func setFrameIfNeeded(_ frame: NSRect, for window: NSWindow) {
        guard !window.frame.equalTo(frame) else { return }
        window.setFrame(frame, display: false)
    }

    private func setupWindows() {
        notchPanelController = NotchPanelController(
            mediaManager: mediaManager,
            clipboardManager: clipboardManager,
            fileShelfManager: fileShelfManager,
            onOpenSettings: { [weak self] in
                self?.openSettings()
            },
            isFileShelfEnabled: { [weak self] in self?.enableFileShelf ?? false },
            isClipboardEnabled: { [weak self] in self?.enableClipboardHistory ?? false },
            hoverDelay: { [weak self] in self?.hoverDelay ?? 0.0 }
        )
        notchPanelController?.start()
    }

    // MARK: - Rest Windows Setup

    func setupRestWindows() {
        guard let screen = NSScreen.main else { return }

        let blockingView = RestBlockingView(restManager: restManager)
        let blockingHostingView = NSHostingView(rootView: blockingView)

        let blockingWindow = RestBlockWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        blockingWindow.isOpaque = true
        blockingWindow.backgroundColor = .black
        blockingWindow.level = NSWindow.Level(Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
        blockingWindow.contentView = blockingHostingView
        blockingWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        blockingWindow.hidesOnDeactivate = false
        self.restBlockingWindow = blockingWindow
    }

    func handleRestStateChange(_ state: RestState) {
        switch state {
        case .idle, .working:
            restWarningWindow?.orderOut(nil)
            restBlockingWindow?.orderOut(nil)

        case .warning:
            restBlockingWindow?.orderOut(nil)

        case .resting:
            restWarningWindow?.orderOut(nil)

            if let screen = NSScreen.main, let w = restBlockingWindow {
                w.setFrame(screen.frame, display: true)
                w.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    // MARK: - Combine Observers

    private func setupCombineObservers() {
        UserDefaults.standard.publisher(for: \.enableClipboardHistory)
            .sink { [weak self] _ in self?.updateClipboardMonitoring() }
            .store(in: &cancellables)

        UserDefaults.standard.publisher(for: \.enablePasteWithoutFormatting)
            .sink { [weak self] _ in self?.updatePasteMonitoring() }
            .store(in: &cancellables)

        UserDefaults.standard.publisher(for: \.enableCtrlXCutPaste)
            .dropFirst()
            .sink { [weak self] _ in self?.updateFileCutPasteMonitoring() }
            .store(in: &cancellables)

        UserDefaults.standard.publisher(for: \.showMenuBarIcon)
            .sink { [weak self] _ in self?.updateMenuBarIcon() }
            .store(in: &cancellables)

        UserDefaults.standard.publisher(for: \.enableFileShelf)
            .sink { [weak self] _ in self?.notchPanelController?.updateContentWindowFrame() }
            .store(in: &cancellables)

        UserDefaults.standard.publisher(for: \.launchAtLogin)
            .sink { [weak self] _ in self?.updateLaunchAtLogin() }
            .store(in: &cancellables)

        UserDefaults.standard.publisher(for: \.invertMouseScroll)
            .sink { _ in ScrollManager.shared.updateSettings() }
            .store(in: &cancellables)

        UserDefaults.standard.publisher(for: \.invertTrackpadScroll)
            .sink { _ in ScrollManager.shared.updateSettings() }
            .store(in: &cancellables)

        UserDefaults.standard.publisher(for: \.enableThreeFingerMiddleClick)
            .sink { _ in
                ThreeFingerClickManager.shared.updateMonitoringState()
            }
            .store(in: &cancellables)

        UserDefaults.standard.publisher(for: \.enableCapsLockNoDelay)
            .dropFirst()
            .sink { enabled in CapsLockNoDelayManager.shared.setEnabled(enabled) }
            .store(in: &cancellables)

        UserDefaults.standard.publisher(for: \.enableWindowSwitcher)
            .sink { enabled in
                if enabled {
                    WindowSwitcherManager.shared.start()
                } else {
                    WindowSwitcherManager.shared.stop()
                }
            }
            .store(in: &cancellables)

        UserDefaults.standard.publisher(for: \.enableDockPreviews)
            .sink { enabled in
                if enabled {
                    DockPreviewManager.shared.start()
                } else {
                    DockPreviewManager.shared.stop()
                }
            }
            .store(in: &cancellables)

        WindowSwitcherManager.shared.$isSwitcherVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                guard let self = self, let window = self.windowSwitcherWindow else { return }
                if visible {
                    self.lastWindowSwitcherIDs = WindowSwitcherManager.shared.windows.map(\.id)
                    DispatchQueue.main.async {
                        self.layoutWindowSwitcherWindow(window)
                        window.alphaValue = 0
                        window.orderFrontRegardless()
                        NSAnimationContext.runAnimationGroup { context in
                            context.duration = 0.1
                            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                            window.animator().alphaValue = 1
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.lastWindowSwitcherIDs = []
                        window.alphaValue = 0
                        window.orderOut(nil)
                    }
                }
            }
            .store(in: &cancellables)

        DockPreviewManager.shared.$isPreviewVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                guard let self = self, let window = self.dockPreviewWindow else { return }
                if visible {
                    DispatchQueue.main.async {
                        self.layoutDockPreviewWindow(window)
                        window.alphaValue = 0
                        window.orderFrontRegardless()
                        NSAnimationContext.runAnimationGroup { context in
                            context.duration = 0.08
                            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                            window.animator().alphaValue = 1
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        window.alphaValue = 0
                        window.orderOut(nil)
                    }
                }
            }
            .store(in: &cancellables)

        DockPreviewManager.shared.$windows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self,
                    let window = self.dockPreviewWindow,
                    DockPreviewManager.shared.isPreviewVisible
                else { return }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    self.layoutDockPreviewWindow(window)
                }
            }
            .store(in: &cancellables)

        WindowSwitcherManager.shared.$windows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] windows in
                guard let self = self,
                    let window = self.windowSwitcherWindow,
                    WindowSwitcherManager.shared.isSwitcherVisible
                else { return }

                let currentIDs = windows.map(\.id)
                guard currentIDs != self.lastWindowSwitcherIDs else { return }
                self.lastWindowSwitcherIDs = currentIDs

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.layoutWindowSwitcherWindow(window)
                }
            }
            .store(in: &cancellables)

        restManager.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.handleRestStateChange(state) }
            .store(in: &cancellables)
    }

    // MARK: - Menu Bar Icon

    func updateMenuBarIcon() {
        if showMenuBarIcon {
            if statusItem == nil {
                statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let icon = NSImage(named: "MenuBarLogo") {
                    icon.isTemplate = false
                    statusItem?.button?.image = icon
                } else {
                    statusItem?.button?.image = NSImage(
                        systemSymbolName: "music.note", accessibilityDescription: "NotchMore")
                }
                statusItem?.button?.imagePosition = .imageOnly

                let menu = NSMenu()
                let settingsItem = NSMenuItem(
                    title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
                settingsItem.target = self
                menu.addItem(settingsItem)
                menu.addItem(NSMenuItem.separator())
                let quitItem = NSMenuItem(
                    title: "Quit NotchMore", action: #selector(NSApplication.terminate(_:)),
                    keyEquivalent: "q")
                menu.addItem(quitItem)
                statusItem?.menu = menu
            }
        } else {
            if let statusItem = statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
        }
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: controller)
            window.title = "NotchMore Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 700, height: 560))
            window.center()
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            settingsWindow = window

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(settingsWindowWillClose),
                name: NSWindow.willCloseNotification,
                object: window
            )
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.level = .floating
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.settingsWindow?.level = .normal
        }
    }

    @objc func openOnboarding() {
        if onboardingWindow == nil {
            let controller = NSHostingController(
                rootView: OnboardingView { [weak self] in
                    self?.closeOnboarding()
                }
            )
            let window = NSWindow(contentViewController: controller)
            window.title = "Set Up NotchMore"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 820, height: 720))
            window.center()
            window.isReleasedWhenClosed = false
            onboardingWindow = window

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(onboardingWindowWillClose),
                name: NSWindow.willCloseNotification,
                object: window
            )
        }

        NSApp.setActivationPolicy(.regular)
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeOnboarding() {
        onboardingWindow?.close()
    }

    @objc private func settingsWindowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func onboardingWindowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding_v1")
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore_v1")
        NSApp.setActivationPolicy(.accessory)
    }

    func updateClipboardMonitoring() {
        if enableClipboardHistory {
            clipboardManager.startMonitoring()
        } else {
            clipboardManager.stopMonitoring()
        }
    }

    func updatePasteMonitoring() {
        if enablePasteWithoutFormatting {
            pasteManager.startMonitoring()
        } else {
            pasteManager.stopMonitoring()
        }
    }

    func updateFileCutPasteMonitoring() {
        if enableCtrlXCutPaste {
            fileCutPasteManager.startMonitoring()
        } else {
            fileCutPasteManager.stopMonitoring()
        }
    }

    // MARK: - Launch at Login

    func updateLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp

            do {
                if launchAtLogin {
                    guard service.status != .enabled else { return }
                    try service.register()
                } else {
                    guard service.status == .enabled else { return }
                    try service.unregister()
                }
            } catch {
                #if DEBUG
                print("Failed to update login item: \(error)")
                #endif
            }
        }
    }

    // MARK: - Observer handling for Screen Layout

    @objc private func screenConfigDidChange(_ notification: Notification) {
        notchPanelController?.start()
    }

    deinit {
        if let keyMonitor = globalKeyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - UserDefaults

extension UserDefaults {
    @objc dynamic var enableClipboardHistory: Bool {
        return bool(forKey: "enableClipboardHistory")
    }
    @objc dynamic var enablePasteWithoutFormatting: Bool {
        return bool(forKey: "enablePasteWithoutFormatting")
    }
    @objc dynamic var showMenuBarIcon: Bool {
        return bool(forKey: "showMenuBarIcon")
    }
    @objc dynamic var enableFileShelf: Bool {
        return bool(forKey: "enableFileShelf")
    }
    @objc dynamic var launchAtLogin: Bool {
        return bool(forKey: "launchAtLogin")
    }
    @objc dynamic var invertMouseScroll: Bool {
        return bool(forKey: "invertMouseScroll")
    }
    @objc dynamic var invertTrackpadScroll: Bool {
        return bool(forKey: "invertTrackpadScroll")
    }
    @objc dynamic var enableRestEyes: Bool {
        return bool(forKey: "enableRestEyes")
    }
    @objc dynamic var enableWindowSwitcher: Bool {
        return bool(forKey: "enableWindowSwitcher")
    }
    @objc dynamic var enableDockPreviews: Bool {
        return bool(forKey: "enableDockPreviews")
    }
    @objc dynamic var enableThreeFingerMiddleClick: Bool {
        return bool(forKey: "enableThreeFingerMiddleClick")
    }
    @objc dynamic var enableCapsLockNoDelay: Bool {
        return bool(forKey: "enableCapsLockNoDelay")
    }
    @objc dynamic var restIntervalMinutes: Int {
        return integer(forKey: "restIntervalMinutes")
    }
    @objc dynamic var restDurationSeconds: Int {
        return integer(forKey: "restDurationSeconds")
    }

    @objc dynamic var enableCtrlXCutPaste: Bool {
        return bool(forKey: "enableCtrlXCutPaste")
    }
}
