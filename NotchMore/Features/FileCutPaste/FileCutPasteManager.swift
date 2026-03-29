import Foundation
import AppKit
import CoreGraphics

private func fileCutPasteCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let refcon = refcon {
            let manager = Unmanaged<FileCutPasteManager>.fromOpaque(refcon).takeUnretainedValue()
            if let tap = manager.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown, let refcon = refcon else {
        return Unmanaged.passUnretained(event)
    }

    let manager = Unmanaged<FileCutPasteManager>.fromOpaque(refcon).takeUnretainedValue()
    return manager.handleKeyEvent(event)
}

class FileCutPasteManager {
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isCutPending = false

    private var isFinderFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
    }

    func startMonitoring() {
        guard eventTap == nil else { return }

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let eventMask: CGEventMask = 1 << CGEventType.keyDown.rawValue

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: fileCutPasteCallback,
            userInfo: refcon
        ) else {
            print("FileCutPasteManager: Could not create event tap.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stopMonitoring() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        isCutPending = false
    }

    fileprivate func handleKeyEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        // Only intercept when Finder is the frontmost app
        guard isFinderFrontmost else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        let hasCmd = flags.contains(.maskCommand)
        let hasShift = flags.contains(.maskShift)
        let hasOpt = flags.contains(.maskAlternate)
        let hasCtrl = flags.contains(.maskControl)

        // Only handle Cmd+key with no extra modifiers
        guard hasCmd, !hasShift, !hasOpt, !hasCtrl else {
            return Unmanaged.passUnretained(event)
        }

        // Cmd+X (keyCode 7) convert to Cmd+C and mark cut pending
        if keyCode == 7 {
            isCutPending = true
            event.setIntegerValueField(.keyboardEventKeycode, value: 8)
            return Unmanaged.passUnretained(event)
        }

        // Cmd+V (keyCode 9) if cut is pending, convert to Opt+Cmd+V (move)
        if keyCode == 9 && isCutPending {
            isCutPending = false
            event.flags = [.maskCommand, .maskAlternate]
            return Unmanaged.passUnretained(event)
        }

        // Cmd+C (keyCode 8) regular copy, clear cut state
        if keyCode == 8 {
            isCutPending = false
        }

        return Unmanaged.passUnretained(event)
    }

    deinit {
        stopMonitoring()
    }
}
