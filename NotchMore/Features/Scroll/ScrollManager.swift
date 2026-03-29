import Cocoa
import CoreGraphics

func scrollEventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon = refcon {
        let manager = Unmanaged<ScrollManager>.fromOpaque(refcon).takeUnretainedValue()
        return manager.handle(event: event)
    }
    return Unmanaged.passUnretained(event)
}

class ScrollManager: ObservableObject {
    static let shared = ScrollManager()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    private var invertMouse: Bool = false
    private var invertTrackpad: Bool = false
    
    private init() {
        self.invertMouse = UserDefaults.standard.bool(forKey: "invertMouseScroll")
        self.invertTrackpad = UserDefaults.standard.bool(forKey: "invertTrackpadScroll")
    }
    
    func updateSettings() {
        self.invertMouse = UserDefaults.standard.bool(forKey: "invertMouseScroll")
        self.invertTrackpad = UserDefaults.standard.bool(forKey: "invertTrackpadScroll")
        
        if !invertMouse && !invertTrackpad {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }
    
    func startMonitoring() {
        if eventTap != nil { return }
        
        // Check accessibility trust and trigger the system prompt when needed.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        guard AXIsProcessTrustedWithOptions(options as CFDictionary) else {
            print("Accessibility permission required for scroll monitoring.")
            return
        }

        let eventMask = (1 << CGEventType.scrollWheel.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: scrollEventCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            print("Failed to create event tap. Check accessibility permissions.")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("Scroll monitoring started")
    }
    
    func stopMonitoring() {
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
        print("Scroll monitoring stopped")
    }

    fileprivate func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        
        let isTrackpad = isContinuous
        
        let shouldInvert = isTrackpad ? invertTrackpad : invertMouse
        
        if shouldInvert {
            // Invert Delta Y
            let deltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            if deltaY != 0 {
                event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -deltaY)
            }
            
            // Invert Delta X
            let deltaX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            if deltaX != 0 {
                event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -deltaX)
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
}
