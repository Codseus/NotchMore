import Foundation
import Combine
import SwiftUI

enum RestState {
    case idle
    case working
    case warning // 10s before break
    case resting // Screen blocked
}

class RestManager: ObservableObject {
    private static let minimumIntervalMinutes = 5
    private static let defaultIntervalMinutes = 20
    private static let minimumDurationSeconds = 10
    private static let defaultDurationSeconds = 20

    @Published var state: RestState = .idle
    @Published var timeRemaining: TimeInterval = 0
    
    // Settings
    @AppStorage("enableRestEyes") var enableRestEyes: Bool = false
    @AppStorage("restIntervalMinutes") var restIntervalMinutes: Int = defaultIntervalMinutes
    @AppStorage("restDurationSeconds") var restDurationSeconds: Int = defaultDurationSeconds
    
    private var timer: Timer?
    private var warningDuration: TimeInterval = 10
    private var observers: [AnyCancellable] = []

    init() {
        sanitizeStoredSettings()

        UserDefaults.standard.publisher(for: \.enableRestEyes)
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] val in
                guard self?.enableRestEyes != val else { return }
                self?.enableRestEyes = val
                self?.updateState()
            }
            .store(in: &observers)
            
        UserDefaults.standard.publisher(for: \.restIntervalMinutes)
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] val in
                let interval = max(val, Self.minimumIntervalMinutes)
                if interval != val {
                    UserDefaults.standard.set(Self.defaultIntervalMinutes, forKey: "restIntervalMinutes")
                    return
                }
                guard self?.restIntervalMinutes != interval else { return }
                self?.restIntervalMinutes = interval
                self?.restartTimer()
            }
            .store(in: &observers)
            
        updateState()
    }

    private func sanitizeStoredSettings() {
        if UserDefaults.standard.integer(forKey: "restIntervalMinutes") < Self.minimumIntervalMinutes
        {
            UserDefaults.standard.set(Self.defaultIntervalMinutes, forKey: "restIntervalMinutes")
            restIntervalMinutes = Self.defaultIntervalMinutes
        }

        if UserDefaults.standard.integer(forKey: "restDurationSeconds") < Self.minimumDurationSeconds
        {
            UserDefaults.standard.set(Self.defaultDurationSeconds, forKey: "restDurationSeconds")
            restDurationSeconds = Self.defaultDurationSeconds
        }
    }
    
    func updateState() {
        if enableRestEyes {
            startWorkSession()
        } else {
            stop()
        }
    }
    
    private func stop() {
        timer?.invalidate()
        timer = nil
        state = .idle
    }
    
    private func startWorkSession() {
        state = .working
        timeRemaining = TimeInterval(restIntervalMinutes * 60)
        startTimer()
    }
    
    private func restartTimer() {
        if enableRestEyes {
            startWorkSession()
        }
    }
    
    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    
    private func tick() {
        timeRemaining -= 1
        
        switch state {
        case .working:
            if timeRemaining <= warningDuration {
                enterWarning()
            }
        case .warning:
            if timeRemaining <= 0 {
                enterRest()
            }
        case .resting:
            if timeRemaining <= 0 {
                finishRest()
            }
        case .idle:
            break
        }
    }
    
    private func enterWarning() {
        state = .warning
        SystemHUDManager.shared.showRestWarning(secondsRemaining: Int(max(timeRemaining, 0)))
    }
    
    private func enterRest() {
        state = .resting
        timeRemaining = TimeInterval(restDurationSeconds)
        SystemHUDManager.shared.showRestStarted(seconds: restDurationSeconds)
    }
    
    private func finishRest() {
        startWorkSession()
    }
    
    // MARK: - User Actions
    
    func addOneMinute() {
        // Adds 1 minute to the current session (delaying break)
        if state == .warning {
            state = .working
            timeRemaining += 60
            SystemHUDManager.shared.showRestSkipped()
        } else if state == .working {
            timeRemaining += 60
        }
    }
    
    func skipBreak() {
        // Skip this specific break and start a new work cycle
        SystemHUDManager.shared.showRestSkipped()
        startWorkSession()
    }
    
    func skipRest() {
        // If currently resting, stop resting and start work
        if state == .resting {
            SystemHUDManager.shared.showRestSkipped()
            startWorkSession()
        }
    }
}
