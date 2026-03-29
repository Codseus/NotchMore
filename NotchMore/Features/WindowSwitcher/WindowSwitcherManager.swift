import Carbon
import Cocoa
import ScreenCaptureKit
import SwiftUI

@_silgen_name("_AXUIElementGetWindow")
private func axUIElementGetWindow(
    _ axElement: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>
) -> AXError

@_silgen_name("_AXUIElementCreateWithRemoteToken")
private func axUIElementCreateWithRemoteToken(_ token: CFData) -> Unmanaged<AXUIElement>?

private typealias CGSConnectionID = UInt32
private typealias CGSMainConnectionFn = @convention(c) () -> CGSConnectionID
private typealias CGSMoveWindowsFn = @convention(c) (CGSConnectionID, CFArray) -> Void

private let cgsCoreGraphicsHandle = dlopen(
    "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)

private let cgsMainConnectionFn: CGSMainConnectionFn? = {
    guard let symbol = dlsym(cgsCoreGraphicsHandle, "CGSMainConnectionID") else { return nil }
    return unsafeBitCast(symbol, to: CGSMainConnectionFn.self)
}()

private let cgsMoveWindowsToCurrentManagedSpaceFn: CGSMoveWindowsFn? = {
    guard let symbol = dlsym(cgsCoreGraphicsHandle, "CGSMoveWindowsToCurrentManagedSpace") else {
        return nil
    }
    return unsafeBitCast(symbol, to: CGSMoveWindowsFn.self)
}()

@discardableResult
private func cgsMoveWindowToCurrentManagedSpace(_ windowID: CGWindowID) -> Bool {
    guard let mainConnection = cgsMainConnectionFn,
        let moveWindows = cgsMoveWindowsToCurrentManagedSpaceFn
    else {
        return false
    }

    let windowArray = [NSNumber(value: windowID)] as CFArray
    moveWindows(mainConnection(), windowArray)
    return true
}

struct WindowInfo: Identifiable, Equatable {
    let id: CGWindowID
    let appName: String
    let appIcon: NSImage?
    let bundleIdentifier: String?
    let windowTitle: String
    let pid: pid_t
    let frame: CGRect
    var snapshot: NSImage?

    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        return lhs.id == rhs.id
    }
}

class WindowSwitcherManager: ObservableObject {
    @Published var windows: [WindowInfo] = []
    @Published var selectedIndex: Int = 0
    @Published var isSwitcherVisible: Bool = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var snapshotCache: [CGWindowID: NSImage] = [:]
    private var mruPIDs: [pid_t] = []
    private var lastSelectedWindowByPID: [pid_t: CGWindowID] = [:]
    private var activationObserver: Any?
    private var pendingActivation: Bool = false
    private var isRefreshInFlight: Bool = false
    private var refreshRequestID: Int = 0
    private var refreshGeneration: Int = 0

    static let shared = WindowSwitcherManager()

    private init() {
        for app in NSWorkspace.shared.runningApplications
        where
            app.activationPolicy == .regular && app.bundleIdentifier != Bundle.main.bundleIdentifier
        {
            mruPIDs.append(app.processIdentifier)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                app.bundleIdentifier != Bundle.main.bundleIdentifier
            else { return }
            let pid = app.processIdentifier
            mruPIDs.removeAll { $0 == pid }
            mruPIDs.insert(pid, at: 0)
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    private func resolvedApp(sourcePID: pid_t, bundleIdentifier: String?, appName: String)
        -> NSRunningApplication?
    {
        if let app = NSRunningApplication(processIdentifier: sourcePID),
            app.activationPolicy == .regular
        {
            return app
        }

        if let bundleIdentifier {
            if let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == bundleIdentifier && $0.activationPolicy == .regular
            }) {
                return app
            }
        }

        return NSWorkspace.shared.runningApplications.first(where: {
            ($0.localizedName ?? "") == appName && $0.activationPolicy == .regular
        })
    }

    private func runningApp(for window: WindowInfo) -> NSRunningApplication? {
        if let app = NSRunningApplication(processIdentifier: window.pid),
            app.activationPolicy == .regular
        {
            return app
        }

        if let bundleIdentifier = window.bundleIdentifier {
            return NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == bundleIdentifier && $0.activationPolicy == .regular
            })
        }

        return NSWorkspace.shared.runningApplications.first(where: {
            ($0.localizedName ?? "") == window.appName && $0.activationPolicy == .regular
        })
    }

    private func orderedOnScreenWindowIDs() -> [CGWindowID] {
        guard
            let infoList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else {
            return []
        }

        return infoList.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                let windowNumber = info[kCGWindowNumber as String] as? UInt32
            else {
                return nil
            }
            return CGWindowID(windowNumber)
        }
    }

    private func captureSnapshots(for visibleWindows: [SCWindow], generation: Int) async {
        await withTaskGroup(of: (CGWindowID, NSImage?).self) { group in
            for scWindow in visibleWindows {
                group.addTask {
                    let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                    let config = SCStreamConfiguration()
                    let targetWidth: CGFloat = 400
                    let aspectRatio =
                        scWindow.frame.width > 0
                        ? (scWindow.frame.height / scWindow.frame.width) : 1.0
                    config.width = Int(targetWidth)
                    config.height = max(1, Int(targetWidth * aspectRatio))
                    config.showsCursor = false

                    if let cgImage = try? await SCScreenshotManager.captureImage(
                        contentFilter: filter, configuration: config)
                    {
                        let nsImage = NSImage(
                            cgImage: cgImage,
                            size: NSSize(width: cgImage.width, height: cgImage.height))
                        return (CGWindowID(scWindow.windowID), nsImage)
                    }
                    return (CGWindowID(scWindow.windowID), nil)
                }
            }

            for await (windowID, image) in group {
                guard let image else { continue }
                await MainActor.run {
                    self.snapshotCache[windowID] = image
                    guard self.refreshGeneration == generation else { return }
                    if let idx = self.windows.firstIndex(where: { $0.id == windowID }) {
                        self.windows[idx].snapshot = image
                    }
                }
            }
        }
    }

    private func axWindowNumber(of axWindow: AXUIElement) -> CGWindowID? {
        var windowID = CGWindowID(0)
        if axUIElementGetWindow(axWindow, &windowID) == .success, windowID != 0 {
            return windowID
        }

        var numberRef: CFTypeRef?
        let attribute = "AXWindowNumber" as CFString
        guard AXUIElementCopyAttributeValue(axWindow, attribute, &numberRef) == .success,
            let number = numberRef as? NSNumber
        else {
            return nil
        }
        return CGWindowID(number.uint32Value)
    }

    private func matches(windowInfo: WindowInfo, axWindow: AXUIElement) -> Bool {
        if let axNumber = axWindowNumber(of: axWindow), axNumber != windowInfo.id {
            return false
        }

        var titleRef: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(
            axWindow, kAXTitleAttribute as CFString, &titleRef)
        let axTitle = titleResult == .success ? (titleRef as? String) ?? "" : ""

        if !windowInfo.windowTitle.isEmpty && axTitle != windowInfo.windowTitle {
            return false
        }

        guard windowInfo.frame != .zero else {
            return true
        }

        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        guard
            AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionRef)
                == .success,
            AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef)
                == .success,
            let rawPositionValue = positionRef,
            let rawSizeValue = sizeRef
        else {
            return false
        }

        guard CFGetTypeID(rawPositionValue) == AXValueGetTypeID(),
            CFGetTypeID(rawSizeValue) == AXValueGetTypeID()
        else {
            return false
        }

        let positionValue = rawPositionValue as! AXValue
        let sizeValue = rawSizeValue as! AXValue

        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetType(positionValue) == .cgPoint,
            AXValueGetType(sizeValue) == .cgSize,
            AXValueGetValue(positionValue, .cgPoint, &position),
            AXValueGetValue(sizeValue, .cgSize, &size)
        else {
            return false
        }

        let tolerance: CGFloat = 16
        return abs(position.x - windowInfo.frame.origin.x) <= tolerance
            && abs(position.y - windowInfo.frame.origin.y) <= tolerance
            && abs(size.width - windowInfo.frame.width) <= tolerance
            && abs(size.height - windowInfo.frame.height) <= tolerance
    }

    private func standardAXWindowList(for pid: pid_t) -> [AXUIElement] {
        let appRef = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &ref)
                == .success,
            let list = ref as? [AXUIElement]
        else {
            return []
        }
        return list
    }

    private func axSubrole(of axWindow: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(axWindow, kAXSubroleAttribute as CFString, &value)
                == .success,
            let subrole = value as? String
        else {
            return nil
        }
        return subrole
    }

    private func bruteForceAXWindowList(for pid: pid_t) -> [AXUIElement] {
        var remoteToken = Data(count: 20)
        remoteToken.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        remoteToken.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
        remoteToken.replaceSubrange(
            8..<12, with: withUnsafeBytes(of: Int32(0x636f_636f)) { Data($0) })

        var windows: [AXUIElement] = []
        let start = DispatchTime.now().uptimeNanoseconds
        let maxScanDurationNs: UInt64 = 250_000_000

        for axID: UInt64 in 0..<4000 {
            remoteToken.replaceSubrange(12..<20, with: withUnsafeBytes(of: axID) { Data($0) })

            guard let unmanaged = axUIElementCreateWithRemoteToken(remoteToken as CFData) else {
                continue
            }
            let axWindow = unmanaged.takeRetainedValue()

            guard let subrole = axSubrole(of: axWindow),
                subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole
            else {
                continue
            }

            windows.append(axWindow)

            if DispatchTime.now().uptimeNanoseconds - start > maxScanDurationNs {
                break
            }
        }

        return windows
    }

    private func axWindowList(for pid: pid_t) -> [AXUIElement] {
        let regularWindows = standardAXWindowList(for: pid)
        let bruteForceWindows = bruteForceAXWindowList(for: pid)
        guard !bruteForceWindows.isEmpty else { return regularWindows }

        var seenIDs = Set<CGWindowID>()
        var merged: [AXUIElement] = []

        for axWindow in regularWindows + bruteForceWindows {
            if let windowID = axWindowNumber(of: axWindow) {
                if seenIDs.insert(windowID).inserted {
                    merged.append(axWindow)
                }
            } else {
                merged.append(axWindow)
            }
        }

        return merged
    }

    private func candidatePIDs(for windowInfo: WindowInfo) -> [pid_t] {
        var pids: [pid_t] = [windowInfo.pid]

        if let bundleIdentifier = windowInfo.bundleIdentifier {
            pids.append(
                contentsOf: NSRunningApplication.runningApplications(
                    withBundleIdentifier: bundleIdentifier
                )
                .filter { $0.activationPolicy == .regular }
                .map(\.processIdentifier))
        }

        pids.append(
            contentsOf: NSWorkspace.shared.runningApplications
                .filter {
                    ($0.localizedName ?? "") == windowInfo.appName
                        && $0.activationPolicy == .regular
                }
                .map(\.processIdentifier))

        var seen = Set<pid_t>()
        return pids.filter { seen.insert($0).inserted }
    }

    private func raiseAXWindow(_ axWindow: AXUIElement, in appRef: AXUIElement) {
        guard AXIsProcessTrusted() else { return }

        // timeout to prevent system freeze if permission is revoked mid-run
        let timeoutQueue = DispatchQueue.global(qos: .userInitiated)
        let sem = DispatchSemaphore(value: 0)

        timeoutQueue.async {
            AXUIElementSetAttributeValue(appRef, kAXMainWindowAttribute as CFString, axWindow)
            AXUIElementSetAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, axWindow)
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
            sem.signal()
        }
        let result = sem.wait(timeout: .now() + 0.2)
        if result == .timedOut {
            return
        }
    }

    /// Strict raise, matches only exact AXWindowNumber == target window id.
    private func raiseWindowStrictByID(for windowInfo: WindowInfo) -> Bool {
        for pid in candidatePIDs(for: windowInfo) {
            let appRef = AXUIElementCreateApplication(pid)
            let windowList = axWindowList(for: pid)
            guard !windowList.isEmpty else { continue }

            for axWindow in windowList {
                if axWindowNumber(of: axWindow) == windowInfo.id {
                    raiseAXWindow(axWindow, in: appRef)
                    return true
                }
            }
        }

        return false
    }

    private func raiseWindow(for windowInfo: WindowInfo) -> Bool {
        for pid in candidatePIDs(for: windowInfo) {
            let appRef = AXUIElementCreateApplication(pid)
            let windowList = axWindowList(for: pid)
            guard !windowList.isEmpty else { continue }

            for axWindow in windowList {
                if axWindowNumber(of: axWindow) == windowInfo.id {
                    raiseAXWindow(axWindow, in: appRef)
                    return true
                }
            }

            var matchingWindow: AXUIElement?
            for axWindow in windowList where matchingWindow == nil {
                if matches(windowInfo: windowInfo, axWindow: axWindow) {
                    matchingWindow = axWindow
                }
            }

            if let matchingWindow {
                raiseAXWindow(matchingWindow, in: appRef)
                return true
            }
        }

        return false
    }

    private func activateExternalWindow(_ win: WindowInfo) {
        guard let app = runningApp(for: win) else { return }

        let options: NSApplication.ActivationOptions = []

        func requestForegroundActivation(_ target: NSRunningApplication) {
            let appURL =
                target.bundleURL
                ?? (win.bundleIdentifier.flatMap {
                    NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
                })

            guard let appURL else {
                target.unhide()
                _ = target.activate(options: options)
                return
            }

            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            config.hides = false
            config.createsNewApplicationInstance = false
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) {
                reopenedApp, _ in
                let effectiveApp = reopenedApp ?? target
                effectiveApp.unhide()
                _ = effectiveApp.activate(options: options)
            }
        }

        func reopenWindowlessApp(_ target: NSRunningApplication) {
            let appURL =
                target.bundleURL
                ?? (win.bundleIdentifier.flatMap {
                    NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
                })

            guard let appURL else {
                target.unhide()
                _ = target.activate(options: options)
                return
            }

            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            config.hides = false
            config.createsNewApplicationInstance = false

            NSWorkspace.shared.openApplication(at: appURL, configuration: config) {
                reopenedApp, _ in
                if let reopenedApp {
                    reopenedApp.unhide()
                    _ = reopenedApp.activate(options: options)
                } else {
                    target.unhide()
                    _ = target.activate(options: options)
                }
            }
        }

        func activateWithFallback(_ target: NSRunningApplication) {
            target.unhide()
            let didActivate = target.activate(options: options)
            if !didActivate {
                requestForegroundActivation(target)
            }
        }

        guard win.frame != .zero else {
            activateWithFallback(app)
            reopenWindowlessApp(app)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { reopenWindowlessApp(app) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                if let appURL = app.bundleURL
                    ?? (win.bundleIdentifier.flatMap {
                        NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
                    })
                {
                    let openConfig = NSWorkspace.OpenConfiguration()
                    openConfig.activates = true
                    openConfig.hides = false
                    openConfig.createsNewApplicationInstance = false
                    NSWorkspace.shared.open(
                        [], withApplicationAt: appURL, configuration: openConfig
                    ) { _, _ in }
                }
                activateWithFallback(app)
            }
            return
        }

        let isOnCurrentSpace = orderedOnScreenWindowIDs().contains(win.id)
        if !isOnCurrentSpace {
            _ = cgsMoveWindowToCurrentManagedSpace(win.id)
        }

        requestForegroundActivation(app)

        let firstRaise = raiseWindowStrictByID(for: win)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            let secondRaise = self.raiseWindowStrictByID(for: win)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                let thirdRaise = self.raiseWindowStrictByID(for: win)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let fourthRaise = self.raiseWindow(for: win)
                    if !(firstRaise || secondRaise || thirdRaise) {
                        if !fourthRaise {
                            // Only escalate to app activation if focus did not leave the current app.
                            let frontmostPID = NSWorkspace.shared.frontmostApplication?
                                .processIdentifier
                            if frontmostPID != app.processIdentifier {
                                return
                            }

                            activateWithFallback(app)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                _ =
                                    self.raiseWindowStrictByID(for: win)
                                    || self.raiseWindow(for: win)
                            }
                        }
                    }
                }
            }
        }
    }

    private func activateWindow(_ win: WindowInfo) {
        lastSelectedWindowByPID[win.pid] = win.id
        activateExternalWindow(win)
    }

    private func hideSwitcherThenActivate(_ win: WindowInfo) {
        hideSwitcher()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            self.activateWindow(win)
        }
    }

    func activateWindowInfo(_ win: WindowInfo) {
        hideSwitcherThenActivate(win)
    }

    func start() {
        if eventTap == nil {
            setupEventTap()
        }
    }

    func stop() {
        if let eventTap = eventTap, let runLoopSource = runLoopSource {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.eventTap = nil
            self.runLoopSource = nil
        }

        DispatchQueue.main.async {
            self.pendingActivation = false
            self.isRefreshInFlight = false
            self.isSwitcherVisible = false
            self.windows = []
        }
    }

    private func setupEventTap() {
        let eventMask =
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { (proxy, type, event, refcon) in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<WindowSwitcherManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handle(event: event, type: type)
        }

        // Diagnostic
        let processPath =
            Bundle.main.executableURL?.path ?? CommandLine.arguments.first ?? "(unknown)"
        let pid = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? "(unknown)"
        let axTrusted = AXIsProcessTrusted()
        print(
            "WindowSwitcherManager.setupEventTap: pid=\(pid) path=\(processPath) bundle=\(bundleID) AXIsProcessTrusted=\(axTrusted)"
        )

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(eventMask),
                callback: callback,
                userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            )
        else {
            let err = String(cString: strerror(errno))
            print(
                "Failed to create event tap. errno=\(err). Process=\(processPath). If running from Xcode, ensure the debug-built .app (DerivedData) has Input Monitoring / Accessibility / Screen Recording permissions. AXIsProcessTrusted=\(axTrusted)"
            )
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let useCommandTab = UserDefaults.standard.bool(forKey: "windowSwitcherUseCommandTab")
        let targetModifier: CGEventFlags = useCommandTab ? .maskCommand : .maskAlternate
        let isModifierPressed = flags.contains(targetModifier)

        if type == .flagsChanged {
            if !isModifierPressed {
                if isSwitcherVisible {
                    DispatchQueue.main.async {
                        guard self.windows.indices.contains(self.selectedIndex) else {
                            self.hideSwitcher()
                            return
                        }
                        let selectedWindow = self.windows[self.selectedIndex]
                        self.hideSwitcherThenActivate(selectedWindow)
                    }
                    return nil
                } else {
                    // Modifier released before the switcher finished loading — flag it so
                    // refreshWindows activates silently when it completes.
                    if isRefreshInFlight {
                        DispatchQueue.main.async { self.pendingActivation = true }
                        return nil
                    }
                }
            }
            return Unmanaged.passRetained(event)
        }

        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let isShiftPressed = flags.contains(.maskShift)

            // Tab = 48
            if keyCode == 48 && isModifierPressed {
                if !isSwitcherVisible {
                    if isRefreshInFlight {
                        return nil
                    }
                    DispatchQueue.main.async {
                        self.pendingActivation = false
                        self.isRefreshInFlight = true
                        self.refreshWindows(showWhenReady: true)
                    }
                } else {
                    DispatchQueue.main.async {
                        if isShiftPressed {
                            self.selectPrevious()
                        } else {
                            self.selectNext()
                        }
                    }
                }
                return nil
            }

            if isSwitcherVisible {
                if keyCode == 123 {  // Left
                    DispatchQueue.main.async { self.selectPrevious() }
                    return nil
                }
                if keyCode == 124 {  // Right
                    DispatchQueue.main.async { self.selectNext() }
                    return nil
                }
                if keyCode == 53 {  // Escape
                    DispatchQueue.main.async { self.hideSwitcher() }
                    return nil
                }
                if keyCode == 36 {  // Enter
                    DispatchQueue.main.async {
                        guard self.windows.indices.contains(self.selectedIndex) else {
                            self.hideSwitcher()
                            return
                        }

                        let selectedWindow = self.windows[self.selectedIndex]
                        self.hideSwitcherThenActivate(selectedWindow)
                    }
                    return nil
                }
            }
        }

        return Unmanaged.passRetained(event)
    }

    func refreshWindows(showWhenReady: Bool = false) {
        refreshRequestID += 1
        let requestID = refreshRequestID

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: false)
                let orderedIDs = orderedOnScreenWindowIDs()
                let visibleWindows = content.windows
                    .filter { $0.windowLayer == 0 }
                    .filter { window in
                        guard let sourcePID = window.owningApplication?.processID else {
                            return false
                        }
                        let bundleId = window.owningApplication?.bundleIdentifier
                        let appName = window.owningApplication?.applicationName ?? ""
                        guard
                            let runningApp = self.resolvedApp(
                                sourcePID: sourcePID, bundleIdentifier: bundleId, appName: appName),
                            let resolvedBundleId = runningApp.bundleIdentifier
                        else { return false }

                        // Don't show own app windows (currently buggy this is just to be safe)
                        if resolvedBundleId == Bundle.main.bundleIdentifier { return false }

                        // Only show apps that live in the Dock
                        if runningApp.activationPolicy != .regular { return false }

                        // Size Filter
                        if Int(window.frame.width) < 50 || Int(window.frame.height) < 50 {
                            return false
                        }

                        if (window.title ?? "").isEmpty { return false }

                        return true
                    }

                // Build the window list seeded with whatever is already in the cache.
                var newWindows: [WindowInfo] = []

                for scWindow in visibleWindows {
                    let sourcePID = scWindow.owningApplication?.processID ?? 0
                    let app = resolvedApp(
                        sourcePID: sourcePID,
                        bundleIdentifier: scWindow.owningApplication?.bundleIdentifier,
                        appName: scWindow.owningApplication?.applicationName ?? ""
                    )
                    let windowID = CGWindowID(scWindow.windowID)
                    let info = WindowInfo(
                        id: windowID,
                        appName: scWindow.owningApplication?.applicationName ?? "",
                        appIcon: app?.icon,
                        bundleIdentifier: app?.bundleIdentifier
                            ?? scWindow.owningApplication?.bundleIdentifier,
                        windowTitle: scWindow.title ?? "",
                        pid: app?.processIdentifier ?? sourcePID,
                        frame: scWindow.frame,
                        snapshot: snapshotCache[windowID]
                    )
                    newWindows.append(info)
                }

                // Add running apps that don't have open windows
                let existingPIDs = Set(newWindows.map { $0.pid })
                for app in NSWorkspace.shared.runningApplications {
                    guard app.activationPolicy == .regular else { continue }
                    guard !existingPIDs.contains(app.processIdentifier) else { continue }
                    guard let bundleId = app.bundleIdentifier,
                        bundleId != Bundle.main.bundleIdentifier
                    else { continue }

                    let fakeWindowID = CGWindowID(app.processIdentifier) + 999000
                    let info = WindowInfo(
                        id: fakeWindowID,
                        appName: app.localizedName ?? "Unknown",
                        appIcon: app.icon,
                        bundleIdentifier: app.bundleIdentifier,
                        windowTitle: "Application",
                        pid: app.processIdentifier,
                        frame: .zero,
                        snapshot: nil
                    )
                    newWindows.append(info)
                }

                // Interleave windows across apps in MRU order so one app with many windows
                // cannot push every other app deeper in the list.
                let mru = self.mruPIDs
                func mruRank(_ pid: pid_t) -> Int {
                    mru.firstIndex(of: pid) ?? Int.max
                }

                let perAppSorted = newWindows.sorted { lhs, rhs in
                    let leftMRU = mruRank(lhs.pid)
                    let rightMRU = mruRank(rhs.pid)
                    if leftMRU != rightMRU { return leftMRU < rightMRU }
                    if lhs.pid != rhs.pid { return lhs.pid < rhs.pid }

                    // Same app: prefer the most recently selected window for that app.
                    let preferredID = self.lastSelectedWindowByPID[lhs.pid]
                    if let preferredID {
                        let lhsPreferred = lhs.id == preferredID
                        let rhsPreferred = rhs.id == preferredID
                        if lhsPreferred != rhsPreferred { return lhsPreferred }
                    }

                    // Same app: real windows before windowless placeholders.
                    if (lhs.frame == .zero) != (rhs.frame == .zero) { return rhs.frame == .zero }

                    // Then by on-screen z-order.
                    let li = orderedIDs.firstIndex(of: lhs.id) ?? Int.max
                    let ri = orderedIDs.firstIndex(of: rhs.id) ?? Int.max
                    if li != ri { return li < ri }

                    return lhs.windowTitle.localizedCaseInsensitiveCompare(rhs.windowTitle)
                        == .orderedAscending
                }

                var windowsByPID: [pid_t: [WindowInfo]] = [:]
                for window in perAppSorted {
                    windowsByPID[window.pid, default: []].append(window)
                }

                let appOrder = windowsByPID.keys.sorted { leftPID, rightPID in
                    let leftMRU = mruRank(leftPID)
                    let rightMRU = mruRank(rightPID)
                    if leftMRU != rightMRU { return leftMRU < rightMRU }
                    return leftPID < rightPID
                }

                var interleaved: [WindowInfo] = []
                var round = 0
                while true {
                    var appended = false
                    for pid in appOrder {
                        guard let bucket = windowsByPID[pid], round < bucket.count else { continue }
                        interleaved.append(bucket[round])
                        appended = true
                    }
                    if !appended { break }
                    round += 1
                }

                newWindows = interleaved

                let finalWindows = newWindows
                let uncachedWindows = visibleWindows.filter {
                    self.snapshotCache[CGWindowID($0.windowID)] == nil
                }

                let currentGeneration = await MainActor.run { () -> Int? in
                    guard requestID == self.refreshRequestID else { return nil }
                    self.refreshGeneration += 1
                    self.windows = finalWindows
                    self.isRefreshInFlight = false
                    if self.windows.isEmpty {
                        self.selectedIndex = 0
                    } else {
                        self.selectedIndex = min(max(0, self.selectedIndex), self.windows.count - 1)
                        if self.windows.count > 1 {
                            self.selectedIndex = 1
                        }
                    }

                    if showWhenReady {
                        if self.pendingActivation {
                            self.pendingActivation = false
                            if self.windows.indices.contains(self.selectedIndex) {
                                let win = self.windows[self.selectedIndex]
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                                    [weak self] in
                                    self?.activateWindow(win)
                                }
                            }
                        } else {
                            self.showSwitcher()
                        }
                    }
                    return self.refreshGeneration
                }

                guard let currentGeneration else { return }

                if !uncachedWindows.isEmpty {
                    await self.captureSnapshots(for: uncachedWindows, generation: currentGeneration)
                }
            } catch {
                await MainActor.run {
                    guard requestID == self.refreshRequestID else { return }
                    self.isRefreshInFlight = false
                    self.pendingActivation = false
                }
                print("Failed to fetch windows via SCK: \(error)")
            }
        }
    }

    func selectNext() {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % windows.count
    }

    func selectPrevious() {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + windows.count) % windows.count
    }

    func showSwitcher() {
        isSwitcherVisible = true
    }

    func hideSwitcher() {
        isSwitcherVisible = false
        windows = []
    }
}
