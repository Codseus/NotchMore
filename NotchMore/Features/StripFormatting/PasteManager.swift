import SwiftUI
import CoreGraphics

private func pasteEventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let refcon = refcon {
            let manager = Unmanaged<PasteManager>.fromOpaque(refcon).takeUnretainedValue()
            if let tap = manager.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown else { return Unmanaged.passUnretained(event) }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags

    // Check for Cmd+V (keyCode 9) without Shift/Option/Control
    guard keyCode == 9,
          flags.contains(.maskCommand),
          !flags.contains(.maskShift),
          !flags.contains(.maskAlternate),
          !flags.contains(.maskControl) else {
        return Unmanaged.passUnretained(event)
    }

    // Skip if pasteboard contains files, stripping destroys file refences.
    let pb = NSPasteboard.general
    let hasFiles = pb.types?.contains(where: { $0 == .fileURL || $0 == .URL }) ?? false
    if hasFiles {
        return Unmanaged.passUnretained(event)
    }

    guard let plainText = pb.string(forType: .string) else {
        return Unmanaged.passUnretained(event)
    }

    pb.clearContents()
    pb.setString(plainText, forType: .string)

    return Unmanaged.passUnretained(event)
}

class PasteManager {
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func startMonitoring() {
        guard eventTap == nil else { return }

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let eventMask: CGEventMask = 1 << CGEventType.keyDown.rawValue

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: pasteEventCallback,
            userInfo: refcon
        ) else {
            print("PasteManager: Could not create event tap. Check Accessibility permissions.")
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
    }

    deinit {
        stopMonitoring()
    }
}
