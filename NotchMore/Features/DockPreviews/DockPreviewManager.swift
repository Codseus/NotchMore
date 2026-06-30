import AppKit
import CoreGraphics
import ScreenCaptureKit
import SwiftUI

@_silgen_name("_AXUIElementGetWindow")
private func dockPreviewAXUIElementGetWindow(
    _ axElement: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>
) -> AXError

@MainActor
final class DockPreviewManager: ObservableObject {
    struct PreviewWindow: Identifiable, Equatable {
        let id: CGWindowID
        let appName: String
        let appIcon: NSImage?
        let bundleIdentifier: String?
        let title: String
        let pid: pid_t
        let frame: CGRect
        var snapshot: NSImage?

        static func == (lhs: PreviewWindow, rhs: PreviewWindow) -> Bool {
            lhs.id == rhs.id
        }
    }

    private struct DockAppCandidate {
        let title: String
        let icon: NSImage?
        let bundleIdentifier: String?
        let bundleURL: URL?
        let runningApp: NSRunningApplication?
        let dockItemFrame: CGRect

        var stableIdentifier: String {
            bundleIdentifier ?? bundleURL?.path ?? title
        }
    }

    @Published var windows: [PreviewWindow] = []
    @Published var hoveredAppName: String = ""
    @Published var hoveredAppIcon: NSImage?
    @Published var isPreviewVisible: Bool = false
    @Published var anchorPoint: CGPoint = .zero
    @Published var anchorFrame: CGRect = .zero

    static let shared = DockPreviewManager()

    private var pollingTimer: Timer?
    private var hoverWorkItem: DispatchWorkItem?
    private var hideWorkItem: DispatchWorkItem?
    private var hoveredDockIdentifier: String?
    private var visibleDockIdentifier: String?
    private var visibleRunningApp: NSRunningApplication?
    private var snapshotCache: [CGWindowID: NSImage] = [:]
    private var previewWindowFrame: CGRect = .zero
    private var refreshID = 0
    private var didLogMissingAccessibility = false

    private let hoverDelay: TimeInterval = 0.12
    private let hideDelay: TimeInterval = 0.16
    private let pollingInterval: TimeInterval = 0.04

    private init() {}

    func start() {
        guard pollingTimer == nil else { return }
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.pollMouseLocation()
            }
        }
        RunLoop.main.add(pollingTimer!, forMode: .common)
    }

    func stop() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
        hideWorkItem?.cancel()
        hideWorkItem = nil
        hidePreview()
    }

    func setPreviewWindowFrame(_ frame: CGRect) {
        previewWindowFrame = frame
    }

    func activate(_ preview: PreviewWindow) {
        hidePreview()
        let info = WindowInfo(
            id: preview.id,
            appName: preview.appName,
            appIcon: preview.appIcon,
            bundleIdentifier: preview.bundleIdentifier,
            windowTitle: preview.title,
            pid: preview.pid,
            frame: preview.frame,
            snapshot: preview.snapshot
        )
        WindowSwitcherManager.shared.activateWindowInfo(info)
    }

    private func pollMouseLocation() {
        let mouse = NSEvent.mouseLocation

        guard isLikelyNearDock(mouse) else {
            if isPreviewVisible, isPointerInPreviewInteractionArea(mouse) {
                hideWorkItem?.cancel()
                hideWorkItem = nil
                return
            }

            hoveredDockIdentifier = nil
            hoverWorkItem?.cancel()
            scheduleHidePreview()
            return
        }

        guard let hoveredApp = dockAppUnderMouse(at: mouse) else {
            if isDockItemUnderMouse(at: mouse) {
                hoveredDockIdentifier = nil
                hoverWorkItem?.cancel()
                hidePreview()
                return
            }

            hoveredDockIdentifier = nil
            hoverWorkItem?.cancel()
            scheduleHidePreview()
            return
        }

        if hoveredApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            scheduleHidePreview()
            return
        }

        hideWorkItem?.cancel()
        hideWorkItem = nil

        let dockIdentifier = hoveredApp.stableIdentifier
        let stableFrame = stableDockItemFrame(hoveredApp.dockItemFrame, near: mouse)
        anchorPoint = CGPoint(x: stableFrame.midX, y: stableFrame.midY)
        anchorFrame = stableFrame

        if isPreviewVisible, dockIdentifier == visibleDockIdentifier {
            return
        }

        if dockIdentifier == hoveredDockIdentifier {
            return
        }

        hoveredDockIdentifier = dockIdentifier
        hoverWorkItem?.cancel()

        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard hoveredApp.stableIdentifier == self.hoveredDockIdentifier else { return }
                await self.showPreview(for: hoveredApp)
            }
        }
        hoverWorkItem = item
        if isPreviewVisible {
            item.perform()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + hoverDelay, execute: item)
        }
    }

    private func showPreview(for app: DockAppCandidate) async {
        let dockIdentifier = app.stableIdentifier
        refreshID += 1
        let requestID = refreshID
        hoveredAppName = app.title
        hoveredAppIcon = app.icon
        visibleDockIdentifier = dockIdentifier
        visibleRunningApp = app.runningApp
        windows = []
        isPreviewVisible = false

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
            let scWindows = content.windows
                .filter { $0.windowLayer == 0 }
                .filter { window in
                    guard let owner = window.owningApplication else { return false }
                    let ownerName = normalizedName(owner.applicationName)
                    let sameApp = owner.bundleIdentifier == app.bundleIdentifier
                        || owner.processID == app.runningApp?.processIdentifier
                        || ownerName == normalizedName(app.title)
                    guard sameApp else { return false }
                    guard Int(window.frame.width) >= 80, Int(window.frame.height) >= 80 else {
                        return false
                    }
                    return !(window.title ?? "").isEmpty
                }

            let previews = scWindows.map { window in
                let windowID = CGWindowID(window.windowID)
                return PreviewWindow(
                    id: windowID,
                    appName: app.title,
                    appIcon: app.icon,
                    bundleIdentifier: app.bundleIdentifier,
                    title: window.title ?? "Window",
                    pid: app.runningApp?.processIdentifier
                        ?? window.owningApplication?.processID ?? 0,
                    frame: window.frame,
                    snapshot: snapshotCache[windowID]
                )
            }

            guard requestID == refreshID else { return }

            guard !previews.isEmpty else {
                hidePreview()
                return
            }

            windows = previews
            isPreviewVisible = true

            let uncached = scWindows.filter { snapshotCache[CGWindowID($0.windowID)] == nil }
            await captureSnapshots(for: uncached, requestID: requestID)
        } catch {
            print("DockPreviewManager: failed to fetch windows: \(error)")
            hidePreview()
        }
    }

    func close(_ preview: PreviewWindow) {
        performButtonAction("AXCloseButton", for: preview)
        hidePreview()
    }

    func minimize(_ preview: PreviewWindow) {
        if !performButtonAction("AXMinimizeButton", for: preview),
            let axWindow = axWindow(for: preview)
        {
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, true as CFTypeRef)
        }
        hidePreview()
    }

    func zoom(_ preview: PreviewWindow) {
        performButtonAction("AXZoomButton", for: preview)
        hidePreview()
    }

    func quitHoveredApplication() {
        guard let app = visibleRunningApp,
            app.bundleIdentifier != Bundle.main.bundleIdentifier
        else {
            return
        }

        _ = app.terminate()
        hidePreview()
    }

    private func captureSnapshots(for windows: [SCWindow], requestID: Int) async {
        await withTaskGroup(of: (CGWindowID, NSImage?).self) { group in
            for window in windows {
                group.addTask {
                    let filter = SCContentFilter(desktopIndependentWindow: window)
                    let config = SCStreamConfiguration()
                    let targetWidth: CGFloat = 360
                    let aspect =
                        window.frame.width > 0 ? window.frame.height / window.frame.width : 1
                    config.width = Int(targetWidth)
                    config.height = max(1, Int(targetWidth * aspect))
                    config.showsCursor = false

                    guard
                        let cgImage = try? await SCScreenshotManager.captureImage(
                            contentFilter: filter, configuration: config)
                    else {
                        return (CGWindowID(window.windowID), nil)
                    }

                    return (
                        CGWindowID(window.windowID),
                        NSImage(
                            cgImage: cgImage,
                            size: NSSize(width: cgImage.width, height: cgImage.height))
                    )
                }
            }

            for await (windowID, image) in group {
                guard requestID == refreshID, let image else { continue }
                snapshotCache[windowID] = image
                if let index = self.windows.firstIndex(where: { $0.id == windowID }) {
                    self.windows[index].snapshot = image
                }
            }
        }
    }

    private func hidePreview() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        refreshID += 1
        isPreviewVisible = false
        visibleDockIdentifier = nil
        visibleRunningApp = nil
        windows = []
        anchorFrame = .zero
    }

    private func scheduleHidePreview() {
        guard isPreviewVisible else { return }
        guard hideWorkItem == nil else { return }

        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.hideWorkItem = nil
                self?.hidePreview()
            }
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay, execute: item)
    }

    private func isPointerInPreviewInteractionArea(_ point: CGPoint) -> Bool {
        guard !previewWindowFrame.isEmpty else { return false }

        if previewWindowFrame.insetBy(dx: -28, dy: -28).contains(point) {
            return true
        }

        let dockFrame = anchorFrame.isEmpty
            ? CGRect(x: anchorPoint.x - 24, y: anchorPoint.y - 24, width: 48, height: 48)
            : anchorFrame.insetBy(dx: -16, dy: -16)
        let bridge = previewWindowFrame.union(dockFrame).insetBy(dx: -18, dy: -18)

        return bridge.contains(point)
    }

    private func isDockItemUnderMouse(at point: CGPoint) -> Bool {
        guard AXIsProcessTrusted(),
            let dock = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == "com.apple.dock"
            })
        else {
            return false
        }

        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
        for candidate in accessibilityPoints(for: point) {
            var element: AXUIElement?
            let error = AXUIElementCopyElementAtPosition(
                dockElement,
                Float(candidate.x),
                Float(candidate.y),
                &element
            )
            guard error == .success, let element else { continue }
            if isDockItem(element) {
                return true
            }
        }

        return false
    }

    private func isDockItem(_ element: AXUIElement) -> Bool {
        var current: AXUIElement? = element

        for _ in 0..<5 {
            guard let item = current else { break }
            let role = stringAttribute(kAXRoleAttribute as CFString, from: item)
            if role == "AXDockItem" {
                return true
            }

            var parent: CFTypeRef?
            guard
                AXUIElementCopyAttributeValue(item, kAXParentAttribute as CFString, &parent)
                    == .success,
                let parentElement = parent
            else { break }
            current = (parentElement as! AXUIElement)
        }

        return false
    }

    private func dockAppUnderMouse(at point: CGPoint) -> DockAppCandidate? {
        guard AXIsProcessTrusted() else {
            if !didLogMissingAccessibility {
                didLogMissingAccessibility = true
                print("DockPreviewManager: Accessibility permission is required.")
            }
            return nil
        }
        guard
            let dock = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == "com.apple.dock"
            })
        else { return nil }

        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
        let candidates = accessibilityPoints(for: point)

        for candidate in candidates {
            var element: AXUIElement?
            let error = AXUIElementCopyElementAtPosition(
                dockElement,
                Float(candidate.x),
                Float(candidate.y),
                &element
            )
            guard error == .success, let element else { continue }
            if let app = dockCandidate(forDockElement: element) {
                return app
            }
        }

        for candidate in candidates {
            if let app = dockCandidateInDockTree(dockElement, containing: candidate) {
                return app
            }
        }

        return nil
    }

    private func accessibilityPoints(for point: CGPoint) -> [CGPoint] {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else {
            return [point]
        }

        let flippedY = screen.frame.maxY - (point.y - screen.frame.minY)
        let flipped = CGPoint(x: point.x, y: flippedY)
        if abs(flipped.y - point.y) < 1 {
            return [point]
        }
        return [point, flipped]
    }

    private func dockCandidate(forDockElement element: AXUIElement) -> DockAppCandidate? {
        var current: AXUIElement? = element

        for _ in 0..<7 {
            guard let item = current else { break }
            if let app = dockCandidate(matching: item) {
                return app
            }

            var parent: CFTypeRef?
            guard
                AXUIElementCopyAttributeValue(item, kAXParentAttribute as CFString, &parent)
                    == .success,
                let parentElement = parent
            else { break }
            current = (parentElement as! AXUIElement)
        }

        return nil
    }

    private func dockCandidateInDockTree(
        _ element: AXUIElement,
        containing point: CGPoint,
        depth: Int = 0
    ) -> DockAppCandidate? {
        guard depth < 7 else { return nil }

        if let frame = frameAttribute(from: element), !frame.insetBy(dx: -2, dy: -2).contains(point)
        {
            return nil
        }

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
            == .success,
            let children = childrenRef as? [AXUIElement]
        {
            for child in children.reversed() {
                if let app = dockCandidateInDockTree(
                    child,
                    containing: point,
                    depth: depth + 1
                ) {
                    return app
                }
            }
        }

        return dockCandidate(matching: element)
    }

    private func dockCandidate(matching element: AXUIElement) -> DockAppCandidate? {
        let dockItemFrame = appKitFrame(fromAccessibilityFrame: frameAttribute(from: element))

        if let url = urlAttribute(from: element) {
            let runningApp = runningApplication(matchingURL: url)
            guard let runningApp else { return nil }
            let bundleIdentifier = Bundle(url: url)?.bundleIdentifier
                ?? Bundle(url: url.standardizedFileURL.resolvingSymlinksInPath())?.bundleIdentifier
                ?? runningApp.bundleIdentifier
            let title = stringAttribute(kAXTitleAttribute as CFString, from: element)
                .flatMap { candidateNames(from: $0).first }
                ?? runningApp.localizedName
                ?? url.deletingPathExtension().lastPathComponent.removingPercentEncoding
                ?? url.deletingPathExtension().lastPathComponent

            return DockAppCandidate(
                title: title,
                icon: runningApp.icon ?? NSWorkspace.shared.icon(forFile: url.path),
                bundleIdentifier: bundleIdentifier,
                bundleURL: url,
                runningApp: runningApp,
                dockItemFrame: dockItemFrame
            )
        }

        let names = [
            stringAttribute("AXIdentifier" as CFString, from: element),
            stringAttribute(kAXTitleAttribute as CFString, from: element),
            stringAttribute(kAXDescriptionAttribute as CFString, from: element),
            stringAttribute(kAXHelpAttribute as CFString, from: element),
            stringAttribute(kAXValueAttribute as CFString, from: element),
        ]
        .compactMap { $0 }
        .flatMap { candidateNames(from: $0) }
        .filter { !$0.isEmpty }

        for name in names {
            if let app = runningApplication(matchingName: name) {
                return DockAppCandidate(
                    title: app.localizedName ?? name,
                    icon: app.icon,
                    bundleIdentifier: app.bundleIdentifier,
                    bundleURL: app.bundleURL,
                    runningApp: app,
                    dockItemFrame: dockItemFrame
                )
            }
        }

        return nil
    }

    private func runningApplication(matchingURL url: URL) -> NSRunningApplication? {
        let standardizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let bundleIdentifier = Bundle(url: url)?.bundleIdentifier
            ?? Bundle(url: standardizedURL)?.bundleIdentifier

        return NSWorkspace.shared.runningApplications.first(where: { app in
            guard app.activationPolicy == .regular else { return false }

            if let bundleIdentifier,
                app.bundleIdentifier?.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
            {
                return true
            }

            let urls = [app.bundleURL, app.executableURL]
                .compactMap { $0?.standardizedFileURL.resolvingSymlinksInPath() }
            if urls.contains(standardizedURL) { return true }

            if let bundleURL = app.bundleURL?.standardizedFileURL.resolvingSymlinksInPath(),
                bundleURL.path == standardizedURL.path
                    || bundleURL.lastPathComponent == standardizedURL.lastPathComponent
            {
                return true
            }

            let urlName = standardizedURL.deletingPathExtension().lastPathComponent
                .removingPercentEncoding ?? standardizedURL.deletingPathExtension()
                .lastPathComponent
            let bundleName = app.bundleURL?.deletingPathExtension().lastPathComponent
            let executableName = app.executableURL?.deletingPathExtension().lastPathComponent

            return [app.localizedName, bundleName, executableName]
                .compactMap { $0 }
                .contains { $0.caseInsensitiveCompare(urlName) == .orderedSame }
        })
    }

    private func runningApplication(matchingName name: String) -> NSRunningApplication? {
        let needle = normalizedName(name)
        guard !needle.isEmpty else { return nil }

        return NSWorkspace.shared.runningApplications.first(where: { app in
            guard app.activationPolicy == .regular else { return false }

            if let bundleIdentifier = app.bundleIdentifier,
                bundleIdentifier.caseInsensitiveCompare(needle) == .orderedSame
            {
                return true
            }

            let candidates = [
                app.localizedName,
                app.bundleURL?.deletingPathExtension().lastPathComponent,
                app.executableURL?.deletingPathExtension().lastPathComponent,
            ]
            .compactMap { $0 }
            .map { normalizedName($0) }

            return candidates.contains { candidate in
                candidate == needle || needle.hasPrefix(candidate + " ")
                    || needle.contains(" " + candidate + " ")
            }
        })
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    @discardableResult
    private func performButtonAction(_ buttonAttribute: String, for preview: PreviewWindow) -> Bool {
        guard let axWindow = axWindow(for: preview) else { return false }

        var buttonRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, buttonAttribute as CFString, &buttonRef)
            == .success,
            let button = buttonRef
        else {
            return false
        }

        return AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
            == .success
    }

    private func axWindow(for preview: PreviewWindow) -> AXUIElement? {
        guard preview.pid > 0 else { return nil }
        let appRef = AXUIElementCreateApplication(preview.pid)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
            == .success,
            let windows = windowsRef as? [AXUIElement]
        else {
            return nil
        }

        for axWindow in windows {
            if axWindowNumber(of: axWindow) == preview.id {
                return axWindow
            }
        }

        return nil
    }

    private func axWindowNumber(of axWindow: AXUIElement) -> CGWindowID? {
        var windowID = CGWindowID(0)
        if dockPreviewAXUIElementGetWindow(axWindow, &windowID) == .success, windowID != 0 {
            return windowID
        }

        var numberRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, "AXWindowNumber" as CFString, &numberRef)
            == .success,
            let number = numberRef as? NSNumber
        else {
            return nil
        }

        return CGWindowID(number.uint32Value)
    }

    private func urlAttribute(from element: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value)
            == .success
        else { return nil }

        if let url = value as? URL {
            return url
        }
        if let string = value as? String {
            return URL(string: string)
        }
        return nil
    }

    private func frameAttribute(from element: AXUIElement) -> CGRect? {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &value) == .success,
            let rawValue = value,
            CFGetTypeID(rawValue) == AXValueGetTypeID()
        {
            let axValue = rawValue as! AXValue
            var frame = CGRect.zero
            guard AXValueGetType(axValue) == .cgRect,
                AXValueGetValue(axValue, .cgRect, &frame)
            else {
                return nil
            }
            return frame
        }

        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef)
                == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
                == .success,
            let rawPosition = positionRef,
            let rawSize = sizeRef,
            CFGetTypeID(rawPosition) == AXValueGetTypeID(),
            CFGetTypeID(rawSize) == AXValueGetTypeID()
        else {
            return nil
        }

        let positionValue = rawPosition as! AXValue
        let sizeValue = rawSize as! AXValue
        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetType(positionValue) == .cgPoint,
            AXValueGetType(sizeValue) == .cgSize,
            AXValueGetValue(positionValue, .cgPoint, &position),
            AXValueGetValue(sizeValue, .cgSize, &size)
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func appKitFrame(fromAccessibilityFrame frame: CGRect?) -> CGRect {
        guard let frame, !frame.isEmpty else { return .zero }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        let screen = NSScreen.screens.first { screen in
            let flippedY = screen.frame.maxY - (center.y - screen.frame.minY)
            return screen.frame.contains(CGPoint(x: center.x, y: flippedY))
                || screen.frame.contains(center)
        } ?? NSScreen.main

        guard let screen else { return frame }

        let flippedY = screen.frame.maxY - (frame.origin.y - screen.frame.minY) - frame.height
        let flippedFrame = CGRect(
            x: frame.origin.x,
            y: flippedY,
            width: frame.width,
            height: frame.height
        )

        if screen.frame.contains(CGPoint(x: flippedFrame.midX, y: flippedFrame.midY)) {
            return flippedFrame
        }

        return frame
    }

    private func stableDockItemFrame(_ frame: CGRect, near point: CGPoint) -> CGRect {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) })
            ?? NSScreen.screens.first(where: { $0.frame.intersects(frame) })
            ?? NSScreen.main
        else {
            return frame
        }

        let screenFrame = screen.frame
        let edge = dockEdge(for: frame, point: point, screenFrame: screenFrame)
        let iconSize = max(48, min(72, max(frame.width, frame.height)))
        let inset: CGFloat = 6

        if isValidDockFrame(frame, on: screenFrame, edge: edge) {
            switch edge {
            case .left:
                return CGRect(
                    x: screenFrame.minX + inset,
                    y: min(max(screenFrame.minY + inset, frame.midY - iconSize / 2), screenFrame.maxY - iconSize - inset),
                    width: iconSize,
                    height: iconSize
                )
            case .right:
                return CGRect(
                    x: screenFrame.maxX - iconSize - inset,
                    y: min(max(screenFrame.minY + inset, frame.midY - iconSize / 2), screenFrame.maxY - iconSize - inset),
                    width: iconSize,
                    height: iconSize
                )
            case .bottom:
                return CGRect(
                    x: min(max(screenFrame.minX + inset, frame.midX - iconSize / 2), screenFrame.maxX - iconSize - inset),
                    y: screenFrame.minY + inset,
                    width: iconSize,
                    height: iconSize
                )
            }
        }

        switch edge {
        case .left:
            return CGRect(
                x: screenFrame.minX + inset,
                y: min(max(screenFrame.minY + inset, point.y - iconSize / 2), screenFrame.maxY - iconSize - inset),
                width: iconSize,
                height: iconSize
            )
        case .right:
            return CGRect(
                x: screenFrame.maxX - iconSize - inset,
                y: min(max(screenFrame.minY + inset, point.y - iconSize / 2), screenFrame.maxY - iconSize - inset),
                width: iconSize,
                height: iconSize
            )
        case .bottom:
            return CGRect(
                x: min(max(screenFrame.minX + inset, point.x - iconSize / 2), screenFrame.maxX - iconSize - inset),
                y: screenFrame.minY + inset,
                width: iconSize,
                height: iconSize
            )
        }
    }

    private enum DockEdge {
        case bottom
        case left
        case right
    }

    private func dockEdge(for frame: CGRect, point: CGPoint, screenFrame: CGRect) -> DockEdge {
        if !frame.isEmpty {
            let leftDistance = abs(frame.minX - screenFrame.minX)
            let rightDistance = abs(screenFrame.maxX - frame.maxX)
            let bottomDistance = abs(frame.minY - screenFrame.minY)
            let closest = min(leftDistance, rightDistance, bottomDistance)

            if closest == leftDistance { return .left }
            if closest == rightDistance { return .right }
            return .bottom
        }

        if point.x < screenFrame.minX + 120 { return .left }
        if point.x > screenFrame.maxX - 120 { return .right }
        return .bottom
    }

    private func isValidDockFrame(_ frame: CGRect, on screenFrame: CGRect, edge: DockEdge) -> Bool {
        guard !frame.isEmpty,
            frame.width >= 24,
            frame.height >= 24,
            frame.width <= 140,
            frame.height <= 140,
            screenFrame.insetBy(dx: -80, dy: -80).intersects(frame)
        else {
            return false
        }

        switch edge {
        case .left:
            return frame.minX < screenFrame.minX + 120
        case .right:
            return frame.maxX > screenFrame.maxX - 120
        case .bottom:
            return frame.minY < screenFrame.minY + 120
        }
    }

    private func isLikelyNearDock(_ point: CGPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else {
            return false
        }

        let visible = screen.visibleFrame
        let frame = screen.frame
        let margin: CGFloat = 120

        return point.y < visible.minY + margin
            || point.x < frame.minX + margin
            || point.x > frame.maxX - margin
    }

    private func candidateNames(from raw: String) -> [String] {
        let cleaned = cleanedDockTitle(raw)
        var names = [cleaned]

        if cleaned.hasSuffix(".app") {
            names.append(String(cleaned.dropLast(4)))
        }

        if let url = URL(string: raw), url.isFileURL {
            names.append(url.deletingPathExtension().lastPathComponent)
        }

        var seen = Set<String>()
        return names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func cleanedDockTitle(_ raw: String) -> String {
        var title = raw
            .replacingOccurrences(of: "file://", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if title.hasSuffix("/") {
            title.removeLast()
        }

        if title.contains("/") {
            title = URL(fileURLWithPath: title).deletingPathExtension().lastPathComponent
        }

        for separator in [",", " - ", " – ", " — "] {
            if let range = title.range(of: separator) {
                title = String(title[..<range.lowerBound])
            }
        }

        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedName(_ raw: String) -> String {
        cleanedDockTitle(raw)
            .replacingOccurrences(of: ".app", with: "", options: [.caseInsensitive])
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
