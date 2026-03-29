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
    @Published var state: RestState = .idle
    @Published var timeRemaining: TimeInterval = 0
    
    // Settings
    @AppStorage("enableRestEyes") var enableRestEyes: Bool = false {
        didSet {
            print("RestManager: enableRestEyes changed to \(enableRestEyes)")
            updateState()
        }
    }
    @AppStorage("restIntervalMinutes") var restIntervalMinutes: Int = 20 { // Time between breaks
        didSet {
            print("RestManager: restIntervalMinutes changed to \(restIntervalMinutes)")
            restartTimer()
        }
    }
    @AppStorage("restDurationSeconds") var restDurationSeconds: Int = 20 { // Duration of break
        didSet { /* No immediate action needed */ }
    }
    
    private var timer: Timer?
    private var warningDuration: TimeInterval = 10
    private var observers: [AnyCancellable] = []

    init() {
        UserDefaults.standard.publisher(for: \.enableRestEyes)
            .sink { [weak self] val in
                self?.enableRestEyes = val
                self?.updateState()
            }
            .store(in: &observers)
            
        UserDefaults.standard.publisher(for: \.restIntervalMinutes)
            .sink { [weak self] val in
                self?.restIntervalMinutes = val
                self?.restartTimer()
            }
            .store(in: &observers)
            
        updateState()
    }
    
    func updateState() {
        if enableRestEyes {
            print("RestManager: Starting work session")
            startWorkSession()
        } else {
            print("RestManager: Stopping")
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
        print("RestManager: Work session started. Time remaining: \(timeRemaining)")
        startTimer()
    }
    
    private func restartTimer() {
        if enableRestEyes {
            print("RestManager: Restarting timer")
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
                print("RestManager: Entering warning state")
                enterWarning()
            }
        case .warning:
            if timeRemaining <= 0 {
                print("RestManager: Entering rest state")
                enterRest()
            }
        case .resting:
            if timeRemaining <= 0 {
                print("RestManager: Finishing rest")
                finishRest()
            }
        case .idle:
            break
        }
    }
    
    private func enterWarning() {
        state = .warning
    }
    
    private func enterRest() {
        state = .resting
        timeRemaining = TimeInterval(restDurationSeconds)
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
        } else if state == .working {
            timeRemaining += 60
        }
    }
    
    func skipBreak() {
        // Skip this specific break and start a new work cycle
        startWorkSession()
    }
    
    func skipRest() {
        // If currently resting, stop resting and start work
        if state == .resting {
            startWorkSession()
        }
    }
}
