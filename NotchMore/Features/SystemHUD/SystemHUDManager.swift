import AppKit
import Combine
import CoreGraphics
import Darwin
import DynamicNotchKit
import IOKit
import IOKit.graphics
import IOKit.ps
import SwiftUI

private let systemDefinedEventType = CGEventType(rawValue: 14)!

private func systemHUDKeyboardCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let refcon {
            let manager = Unmanaged<SystemHUDManager>.fromOpaque(refcon).takeUnretainedValue()
            if let tap = manager.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == systemDefinedEventType, let refcon else {
        return Unmanaged.passUnretained(event)
    }

    let manager = Unmanaged<SystemHUDManager>.fromOpaque(refcon).takeUnretainedValue()
    return manager.handleSystemDefinedEvent(event)
}

private func systemHUDPowerCallback(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let manager = Unmanaged<SystemHUDManager>.fromOpaque(context).takeUnretainedValue()
    manager.handlePowerSourceChange()
}

final class SystemHUDManager: ObservableObject {
    static let shared = SystemHUDManager()

    enum Kind {
        case volume
        case brightness
        case battery
        case rest

        var icon: String {
            switch self {
            case .volume: return "speaker.wave.2.fill"
            case .brightness: return "sun.max.fill"
            case .battery: return "battery.100percent"
            case .rest: return "eye"
            }
        }

        var mutedIcon: String {
            switch self {
            case .volume: return "speaker.slash.fill"
            case .brightness: return icon
            case .battery: return icon
            case .rest: return icon
            }
        }
    }

    struct Item: Equatable {
        let kind: Kind
        let title: String?
        let icon: String?
        let value: Double
        let isMuted: Bool
        let showsLevel: Bool
        let isInteractive: Bool
    }

    private struct PowerState: Equatable {
        let isOnACPower: Bool
        let isCharging: Bool
        let percentage: Double
    }

    @Published var item: Item?

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var powerRunLoopSource: CFRunLoopSource?
    private var notchHUD: DynamicNotch<SystemHUDContentView, EmptyView, EmptyView>?
    private var isHUDVisible = false
    private var visibilityTask: Task<Void, Never>?
    private var hideWorkItem: DispatchWorkItem?
    private var displayServicesHandle: UnsafeMutableRawPointer?
    private var lastPowerState: PowerState?
    private var hasSeededPowerState = false
    private var lastLowBatteryWarningDate: Date?
    private var restAddTimeAction: (() -> Void)?
    private var restSkipAction: (() -> Void)?

    private let step: Double = 1.0 / 16.0
    private let hideDelay: TimeInterval = 1.05
    private let lowBatteryThreshold = 0.20

    private typealias DisplayServicesGetBrightnessFunction = @convention(c) (
        CGDirectDisplayID, UnsafeMutablePointer<Float>
    ) -> Int32
    private typealias DisplayServicesSetBrightnessFunction = @convention(c) (
        CGDirectDisplayID, Float
    ) -> Int32

    func start() {
        guard eventTap == nil else { return }

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let eventMask: CGEventMask = 1 << systemDefinedEventType.rawValue

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: systemHUDKeyboardCallback,
            userInfo: refcon
        ) else {
            print("SystemHUDManager: Could not create HID event tap. Check Input Monitoring/Accessibility permissions.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        startPowerMonitoring()
        Task { @MainActor in
            self.setupNotchHUDIfNeeded()
        }
    }

    func stop() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        visibilityTask?.cancel()
        visibilityTask = nil
        item = nil
        if isHUDVisible {
            Task { @MainActor in
                await notchHUD?.hide()
                isHUDVisible = false
            }
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        if let source = powerRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            powerRunLoopSource = nil
        }
    }

    func showRestWarning(
        secondsRemaining: Int,
        addTimeAction: @escaping () -> Void,
        skipAction: @escaping () -> Void
    ) {
        restAddTimeAction = addTimeAction
        restSkipAction = skipAction
        show(
            item: Item(
                kind: .rest,
                title: "Rest in \(secondsRemaining)s",
                icon: "eye",
                value: Double(secondsRemaining),
                isMuted: false,
                showsLevel: false,
                isInteractive: true
            ),
            autoHide: false
        )
    }

    func showRestStarted(seconds: Int) {
        restAddTimeAction = nil
        restSkipAction = nil
        showNotification(
            kind: .rest,
            title: "Rest your eyes",
            icon: "moon.zzz.fill",
            value: nil
        )
    }

    func showRestSkipped() {
        restAddTimeAction = nil
        restSkipAction = nil
        showNotification(
            kind: .rest,
            title: "Break skipped",
            icon: "forward.fill",
            value: nil
        )
    }

    func showRestTimeAdded() {
        restAddTimeAction = nil
        restSkipAction = nil
        showNotification(
            kind: .rest,
            title: "Added 1 minute",
            icon: "plus.circle.fill",
            value: nil
        )
    }

    func addRestTime() {
        restAddTimeAction?()
    }

    func skipRestBreak() {
        restSkipAction?()
    }

    fileprivate func handleSystemDefinedEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let nsEvent = NSEvent(cgEvent: event),
            nsEvent.subtype.rawValue == 8
        else {
            return Unmanaged.passUnretained(event)
        }

        let data = nsEvent.data1
        let keyCode = (data & 0xFFFF_0000) >> 16
        let keyFlags = (data & 0x0000_FFFF)
        let keyState = (keyFlags & 0xFF00) >> 8
        let isKeyDown = keyState == 0x0A

        guard [0, 1, 2, 3, 7].contains(keyCode) else {
            return Unmanaged.passUnretained(event)
        }

        guard isKeyDown else {
            return nil
        }

        switch keyCode {
        case 0:  // Volume up
            adjustVolume(by: step)
            return nil
        case 1:  // Volume down
            adjustVolume(by: -step)
            return nil
        case 7:  // Mute
            toggleMute()
            return nil
        case 2:  // Brightness up
            if adjustBrightness(by: step) {
                return nil
            }
            showBrightnessAfterSystemChange()
            return Unmanaged.passUnretained(event)
        case 3:  // Brightness down
            if adjustBrightness(by: -step) {
                return nil
            }
            showBrightnessAfterSystemChange()
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func adjustVolume(by delta: Double) {
        let current = currentVolume()
        let value = max(0, min(1, current + delta))
        setVolume(value)
        showLevel(kind: .volume, value: value, isMuted: value == 0)
    }

    private func toggleMute() {
        let muted = isMuted()
        setMuted(!muted)
        showLevel(kind: .volume, value: currentVolume(), isMuted: !muted)
    }

    private func currentVolume() -> Double {
        guard let output = runAppleScript("output volume of (get volume settings)")?
            .stringValue,
            let value = Double(output)
        else {
            return 0
        }
        return max(0, min(1, value / 100.0))
    }

    private func isMuted() -> Bool {
        runAppleScript("output muted of (get volume settings)")?.stringValue == "true"
    }

    private func setVolume(_ value: Double) {
        let output = Int(round(max(0, min(1, value)) * 100))
        _ = runAppleScript("set volume output volume \(output) without output muted")
    }

    private func setMuted(_ muted: Bool) {
        _ = runAppleScript("set volume \(muted ? "with" : "without") output muted")
    }

    private func adjustBrightness(by delta: Double) -> Bool {
        let current = currentBrightness()
        let value = max(0, min(1, current + delta))
        if setBrightness(value) {
            showLevel(kind: .brightness, value: value, isMuted: false)
            return true
        } else {
            return false
        }
    }

    private func showBrightnessAfterSystemChange() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            self.showLevel(kind: .brightness, value: self.currentBrightness(), isMuted: false)
        }
    }

    private func currentBrightness() -> Double {
        if let value = displayServicesBrightness() {
            return value
        }

        for service in displayServices() {
            var brightness: Float = 0
            let result = IODisplayGetFloatParameter(
                service,
                IOOptionBits(0),
                kIODisplayBrightnessKey as CFString,
                &brightness
            )
            IOObjectRelease(service)
            if result == kIOReturnSuccess {
                return Double(max(0, min(1, brightness)))
            }
        }

        return 0
    }

    private func setBrightness(_ value: Double) -> Bool {
        if setDisplayServicesBrightness(value) {
            return true
        }

        var didSet = false
        for service in displayServices() {
            let result = IODisplaySetFloatParameter(
                service,
                IOOptionBits(0),
                kIODisplayBrightnessKey as CFString,
                Float(max(0, min(1, value)))
            )
            IOObjectRelease(service)
            didSet = didSet || result == kIOReturnSuccess
        }
        return didSet
    }

    private func displayServicesBrightness() -> Double? {
        guard let getBrightness = displayServicesFunction(
            named: "DisplayServicesGetBrightness",
            as: DisplayServicesGetBrightnessFunction.self
        ) else {
            return nil
        }

        var brightness: Float = 0
        let result = getBrightness(CGMainDisplayID(), &brightness)
        guard result == 0 else { return nil }
        return Double(max(0, min(1, brightness)))
    }

    private func setDisplayServicesBrightness(_ value: Double) -> Bool {
        guard let setBrightness = displayServicesFunction(
            named: "DisplayServicesSetBrightness",
            as: DisplayServicesSetBrightnessFunction.self
        ) else {
            return false
        }

        return setBrightness(CGMainDisplayID(), Float(max(0, min(1, value)))) == 0
    }

    private func displayServicesFunction<T>(named name: String, as type: T.Type) -> T? {
        if displayServicesHandle == nil {
            displayServicesHandle = dlopen(
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                RTLD_LAZY
            )
        }

        guard let displayServicesHandle,
            let symbol = dlsym(displayServicesHandle, name)
        else {
            return nil
        }

        return unsafeBitCast(symbol, to: type)
    }

    private func displayServices() -> [io_service_t] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        ) == kIOReturnSuccess
        else {
            return []
        }

        var services: [io_service_t] = []
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            services.append(service)
        }
        IOObjectRelease(iterator)
        return services
    }

    private func startPowerMonitoring() {
        guard powerRunLoopSource == nil else { return }

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let source = IOPSNotificationCreateRunLoopSource(systemHUDPowerCallback, context)
            .takeRetainedValue() as CFRunLoopSource?
        else {
            return
        }

        powerRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        handlePowerSourceChange()
    }

    fileprivate func handlePowerSourceChange() {
        guard let state = currentPowerState() else { return }
        defer {
            lastPowerState = state
            hasSeededPowerState = true
        }

        guard hasSeededPowerState else { return }

        if let lastPowerState, lastPowerState.isOnACPower != state.isOnACPower {
            if state.isOnACPower {
                showNotification(
                    kind: .battery,
                    title: state.isCharging ? "Charging" : "Power connected",
                    icon: "bolt.fill",
                    value: state.percentage
                )
            } else {
                showNotification(
                    kind: .battery,
                    title: "On battery",
                    icon: "battery.50percent",
                    value: state.percentage
                )
            }
            return
        }

        if !state.isOnACPower,
            state.percentage <= lowBatteryThreshold,
            shouldShowLowBatteryWarning()
        {
            showNotification(
                kind: .battery,
                title: "Low battery",
                icon: "battery.25percent",
                value: state.percentage
            )
        }
    }

    private func currentPowerState() -> PowerState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let powerSources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return nil
        }

        for powerSource in powerSources {
            guard let description = IOPSGetPowerSourceDescription(info, powerSource)?
                .takeUnretainedValue() as? [String: Any],
                let type = description[kIOPSTypeKey] as? String,
                type == kIOPSInternalBatteryType
            else {
                continue
            }

            let currentCapacity = description[kIOPSCurrentCapacityKey] as? Double
                ?? Double(description[kIOPSCurrentCapacityKey] as? Int ?? 0)
            let maxCapacity = description[kIOPSMaxCapacityKey] as? Double
                ?? Double(description[kIOPSMaxCapacityKey] as? Int ?? 100)
            let percentage = maxCapacity > 0 ? max(0, min(1, currentCapacity / maxCapacity)) : 0
            let powerState = description[kIOPSPowerSourceStateKey] as? String
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false

            return PowerState(
                isOnACPower: powerState == kIOPSACPowerValue,
                isCharging: isCharging,
                percentage: percentage
            )
        }

        return nil
    }

    private func shouldShowLowBatteryWarning() -> Bool {
        let now = Date()
        if let lastLowBatteryWarningDate,
            now.timeIntervalSince(lastLowBatteryWarningDate) < 10 * 60
        {
            return false
        }
        lastLowBatteryWarningDate = now
        return true
    }

    private func showLevel(kind: Kind, value: Double, isMuted: Bool) {
        show(
            item: Item(
                kind: kind,
                title: nil,
                icon: nil,
                value: value,
                isMuted: isMuted,
                showsLevel: true,
                isInteractive: false
            ))
    }

    private func showNotification(kind: Kind, title: String, icon: String, value: Double?) {
        show(
            item: Item(
                kind: kind,
                title: title,
                icon: icon,
                value: value ?? 0,
                isMuted: false,
                showsLevel: value != nil,
                isInteractive: false
            ))
    }

    private func show(item newItem: Item, autoHide: Bool = true) {
        Task { @MainActor in
            self.setupNotchHUDIfNeeded()
            self.item = newItem
            self.configureHUDWindow()

            self.visibilityTask?.cancel()
            self.visibilityTask = Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.isHUDVisible {
                    self.isHUDVisible = true
                    await self.notchHUD?.expand()
                }
                self.configureHUDWindow()
            }

            self.hideWorkItem?.cancel()
            guard autoHide else {
                self.hideWorkItem = nil
                return
            }

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.visibilityTask?.cancel()
                self.visibilityTask = Task { @MainActor [weak self] in
                    guard let self, self.isHUDVisible else { return }
                    await self.notchHUD?.hide()
                    self.isHUDVisible = false
                    self.item = nil
                }
            }
            self.hideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + self.hideDelay, execute: workItem)
        }
    }

    @MainActor
    private func setupNotchHUDIfNeeded() {
        guard notchHUD == nil else {
            configureHUDWindow()
            return
        }

        notchHUD = DynamicNotch(hoverBehavior: []) {
            SystemHUDContentView(manager: self)
        }
        configureHUDWindow()
    }

    @MainActor
    private func configureHUDWindow() {
        guard let window = notchHUD?.windowController?.window else { return }
        window.level = .screenSaver
        window.ignoresMouseEvents = !(item?.isInteractive ?? false)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    @discardableResult
    private func runAppleScript(_ script: String) -> NSAppleEventDescriptor? {
        guard let appleScript = NSAppleScript(source: script) else { return nil }
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)
        if let error {
            print("SystemHUDManager AppleScript error: \(error)")
            return nil
        }
        return result
    }
}

private struct SystemHUDContentView: View {
    @ObservedObject var manager: SystemHUDManager

    var body: some View {
        Group {
            if let item = manager.item {
                if item.isInteractive && item.kind == .rest {
                    restWarning(item)
                } else {
                    compactHUD(item)
                }
            }
        }
    }

    private func compactHUD(_ item: SystemHUDManager.Item) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon(for: item))
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 26)

                Text(title(for: item))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                if item.showsLevel {
                    Text("\(Int(round((item.isMuted ? 0 : item.value) * 100)))")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
            }

            if item.showsLevel {
                segmentedLevel(value: item.isMuted ? 0 : item.value)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, item.showsLevel ? 16 : 14)
        .frame(width: 310, height: item.showsLevel ? 86 : 62)
        .foregroundStyle(.primary)
    }

    private func restWarning(_ item: SystemHUDManager.Item) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon(for: item))
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Rest Eyes")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(Int(item.value)) seconds until break")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 10) {
                Button(action: { manager.addRestTime() }) {
                    Text("+1 min")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 86, height: 28)
                        .background(Color.primary.opacity(0.12))
                        .clipShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: { manager.skipRestBreak() }) {
                    Text("Skip")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 86, height: 28)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(width: 330, height: 112)
        .foregroundStyle(.primary)
    }

    private func segmentedLevel(value: Double) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<16, id: \.self) { index in
                let isFilled = Double(index + 1) / 16.0 <= value + 0.001
                Capsule(style: .continuous)
                    .fill(isFilled ? Color.primary : Color.primary.opacity(0.18))
                    .frame(height: 7)
            }
        }
    }

    private func title(for item: SystemHUDManager.Item) -> String {
        if let title = item.title {
            return title
        }

        switch item.kind {
        case .volume:
            return item.isMuted ? "Muted" : "Volume"
        case .brightness:
            return "Brightness"
        case .battery:
            return "Battery"
        case .rest:
            return "Rest Eyes"
        }
    }

    private func icon(for item: SystemHUDManager.Item) -> String {
        if let icon = item.icon {
            return icon
        }
        return item.isMuted ? item.kind.mutedIcon : item.kind.icon
    }
}
