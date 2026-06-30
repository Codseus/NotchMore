import Foundation
import Cocoa
import CoreGraphics
import SwiftUI

typealias MTDeviceRef = UnsafeRawPointer
typealias MTDeviceCreateListFunc = @convention(c) () -> Unmanaged<CFMutableArray>
typealias MTRegisterContactFrameCallbackFunc = @convention(c) (MTDeviceRef, @convention(c) (MTDeviceRef, UnsafeRawPointer, Int32, Double, Int32) -> Void) -> Void
typealias MTStartFunc = @convention(c) (MTDeviceRef, Int32) -> Void
typealias MTStopFunc = @convention(c) (MTDeviceRef, Int32) -> Void


typealias MTContactCallback = @convention(c) (MTDeviceRef, UnsafeRawPointer, Int32, Double, Int32) -> Void

func mtCallback(device: MTDeviceRef, data: UnsafeRawPointer, numTouches: Int32, timestamp: Double, frame: Int32) {
    ThreeFingerClickManager.shared.updateFingerCount(Int(numTouches))
}

func clickEventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
         print("ThreeFinger: Tap disabled by system! Attempting re-enable.")
         if let tap = ThreeFingerClickManager.shared.eventTap {
             CGEvent.tapEnable(tap: tap, enable: true)
         }
         return Unmanaged.passUnretained(event)
    }
    
    return ThreeFingerClickManager.shared.handleEvent(type: type, event: event)
}

class ThreeFingerClickManager: ObservableObject {
    static let shared = ThreeFingerClickManager()
    
    @AppStorage("enableThreeFingerMiddleClick") var isEnabled: Bool = false {
        didSet {
            updateMonitoringState()
        }
    }
    
    @Published var currentFingerCount: Int = 0
    @Published var permissionStatus: String = "Unknown"
    @Published var serviceStatus: String = "Stopped"
    
    private var isThreeFingerClickActive: Bool = false
    
    private var mtDevices: [AnyObject] = []
    var eventTap: CFMachPort? 
    private var runLoopSource: CFRunLoopSource?
    private var frameworkHandle: UnsafeMutableRawPointer?
    
    private var mtCreateList: MTDeviceCreateListFunc?
    private var mtRegister: MTRegisterContactFrameCallbackFunc?
    private var mtStart: MTStartFunc?
    private var mtStop: MTStopFunc?
    
    private init() {
         updateMonitoringState()
    }
    
    
    func start() {
        serviceStatus = "Starting..."
        
        if !loadFramework() { 
            print("ThreeFinger: Failed to load framework")
            serviceStatus = "Failed: Framework Error"
            return 
        }
        startTouchMonitoring()
        
        if startEventTap() {
            serviceStatus = "Running"
        } else {
            print("ThreeFinger: Service failed to partially start (Event Tap Failed)")
            serviceStatus = "Failed: Event Tap Error"
        }
    }
    
    func stop() {
        stopEventTap()
        stopTouchMonitoring()
        serviceStatus = "Stopped"
    }
    
    func updateMonitoringState() {
        if isEnabled {
            start()
        } else {
            stop()
        }
    }
    
    // MARK: - Framework Loading
    
    private func loadFramework() -> Bool {
        if frameworkHandle != nil { return true }
        
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_NOW) else {
            print("ThreeFinger: Failed to load MultitouchSupport framework")
            return false
        }
        frameworkHandle = handle
        
        let createListSym = dlsym(handle, "MTDeviceCreateList")
        let registerSym = dlsym(handle, "MTRegisterContactFrameCallback")
        let startSym = dlsym(handle, "MTDeviceStart")
        let stopSym = dlsym(handle, "MTDeviceStop")
        
        if let c = createListSym, let r = registerSym, let s = startSym, let st = stopSym {
            mtCreateList = unsafeBitCast(c, to: MTDeviceCreateListFunc.self)
            mtRegister = unsafeBitCast(r, to: MTRegisterContactFrameCallbackFunc.self)
            mtStart = unsafeBitCast(s, to: MTStartFunc.self)
            mtStop = unsafeBitCast(st, to: MTStopFunc.self)
            return true
        }
        
        print("ThreeFinger: Failed to load symbols")
        return false
    }
    
    // MARK: - Touch Monitoring
    
    private func startTouchMonitoring() {
        guard mtDevices.isEmpty else { return }
        
        if let listRef = mtCreateList?() {
            let list = listRef.takeRetainedValue() as NSArray
            self.mtDevices = list as [AnyObject]
            
            for device in mtDevices {
                let devicePtr = unsafeBitCast(device, to: MTDeviceRef.self)
                mtRegister?(devicePtr, mtCallback)
                mtStart?(devicePtr, 0)
            }
        } else {
            print("ThreeFinger: Failed to create device list")
        }
    }
    
    private func stopTouchMonitoring() {
        for device in mtDevices {
            let devicePtr = unsafeBitCast(device, to: MTDeviceRef.self)
            mtStop?(devicePtr, 0)
        }
        mtDevices.removeAll()
    }
    
    func updateFingerCount(_ count: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.currentFingerCount = count
        }
    }
    
    // MARK: - Event Tap
    @discardableResult
    private func startEventTap() -> Bool {
        if eventTap != nil { return true }
        
        
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        permissionStatus = isTrusted ? "Granted" : "Denied/Missing"
        guard isTrusted else {
            print("ThreeFinger: Accessibility permission required for event tap.")
            return false
        }
        
        let eventMask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue) |
                                     (1 << CGEventType.leftMouseUp.rawValue) |
                                     (1 << CGEventType.leftMouseDragged.rawValue) |
                                     (1 << CGEventType.rightMouseDown.rawValue) |
                                     (1 << CGEventType.rightMouseUp.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap, 
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: clickEventCallback,
            userInfo: nil
        ) else {
            
            // Fallback to Session Tap
            guard let sessionTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: clickEventCallback,
                userInfo: nil
            ) else {
                print("ThreeFinger: Could not create any event tap.")
                return false
            }
            
            setupRunLoop(for: sessionTap)
            return true
        }
        
        setupRunLoop(for: tap)
        return true
    }
    
    private func setupRunLoop(for tap: CFMachPort) {
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
    }
    
    private func stopEventTap() {
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
    }
    
    // MARK: - Event Handling Logic
    
    func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .leftMouseDown || type == .rightMouseDown {
            
            if currentFingerCount >= 3 {
                isThreeFingerClickActive = true
                
                event.type = .otherMouseDown
                event.setIntegerValueField(.mouseEventButtonNumber, value: 2) // Middle Button
                return Unmanaged.passUnretained(event)
            }
        } else if type == .leftMouseUp || type == .rightMouseUp {
            if isThreeFingerClickActive {
                isThreeFingerClickActive = false
                
                event.type = .otherMouseUp
                event.setIntegerValueField(.mouseEventButtonNumber, value: 2) // Middle Button
                return Unmanaged.passUnretained(event)
            }
        } else if type == .leftMouseDragged || type == .rightMouseDragged {
            if isThreeFingerClickActive {
                event.type = .otherMouseDragged
                event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
                return Unmanaged.passUnretained(event)
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
}
