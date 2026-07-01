import Foundation
import Combine

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
    
    private var enableRestEyes: Bool = false
    private var restIntervalMinutes: Int = defaultIntervalMinutes
    private var restDurationSeconds: Int = defaultDurationSeconds
    
    private var timer: Timer?
    private var warningDuration: TimeInterval = 10
    private var observers: [AnyCancellable] = []

    init() {
        sanitizeStoredSettings()
        loadStoredSettings()

        UserDefaults.standard.publisher(for: \.enableRestEyes)
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] val in
                self?.setEnabled(val)
            }
            .store(in: &observers)
            
        UserDefaults.standard.publisher(for: \.restIntervalMinutes)
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] val in
                self?.setIntervalMinutes(val)
            }
            .store(in: &observers)

        UserDefaults.standard.publisher(for: \.restDurationSeconds)
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] val in
                self?.setDurationSeconds(val)
            }
            .store(in: &observers)
            
        updateState()
    }

    private func sanitizeStoredSettings() {
        if UserDefaults.standard.integer(forKey: "restIntervalMinutes") < Self.minimumIntervalMinutes
        {
            UserDefaults.standard.set(Self.defaultIntervalMinutes, forKey: "restIntervalMinutes")
        }

        if UserDefaults.standard.integer(forKey: "restDurationSeconds") < Self.minimumDurationSeconds
        {
            UserDefaults.standard.set(Self.defaultDurationSeconds, forKey: "restDurationSeconds")
        }
    }

    private func loadStoredSettings() {
        enableRestEyes = UserDefaults.standard.bool(forKey: "enableRestEyes")
        restIntervalMinutes = max(
            UserDefaults.standard.integer(forKey: "restIntervalMinutes"),
            Self.minimumIntervalMinutes
        )
        restDurationSeconds = max(
            UserDefaults.standard.integer(forKey: "restDurationSeconds"),
            Self.minimumDurationSeconds
        )
    }

    private func setEnabled(_ enabled: Bool) {
        guard enableRestEyes != enabled else { return }
        enableRestEyes = enabled
        updateState()
    }

    private func setIntervalMinutes(_ minutes: Int) {
        guard minutes >= Self.minimumIntervalMinutes else {
            UserDefaults.standard.set(Self.defaultIntervalMinutes, forKey: "restIntervalMinutes")
            return
        }

        guard restIntervalMinutes != minutes else { return }
        restIntervalMinutes = minutes
        restartTimer()
    }

    private func setDurationSeconds(_ seconds: Int) {
        guard seconds >= Self.minimumDurationSeconds else {
            UserDefaults.standard.set(Self.defaultDurationSeconds, forKey: "restDurationSeconds")
            return
        }

        restDurationSeconds = seconds
        if state == .resting {
            timeRemaining = min(timeRemaining, TimeInterval(seconds))
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
            } else {
                showRestWarning()
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
        showRestWarning()
    }

    private func showRestWarning() {
        SystemHUDManager.shared.showRestWarning(
            secondsRemaining: Int(max(timeRemaining, 0)),
            addTimeAction: { [weak self] in
                self?.addOneMinute()
            },
            skipAction: { [weak self] in
                self?.skipBreak()
            }
        )
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
            SystemHUDManager.shared.showRestTimeAdded()
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
