import SwiftUI
import MediaRemoteAdapter

class MediaManager: ObservableObject {
    @Published var currentTrackTitle: String = "Not Playing"
    @Published var currentTrackArtist: String = "No media detected"
    @Published var artwork: NSImage?
    @Published var isPlaying: Bool = false
    @Published var volume: Float = 0.5
    @Published var trackDuration: Double = 0
    @Published var trackElapsed: Double = 0
    
    private let mediaController = MediaController()
    
    init() {
        mediaController.onTrackInfoReceived = { [weak self] trackInfo in
            DispatchQueue.main.async {
                self?.currentTrackTitle = trackInfo.payload.title ?? "Unknown Title"
                self?.currentTrackArtist = trackInfo.payload.artist ?? "Unknown Artist"
                
                // Use shared thumbnail extension
                if let originalArtwork = trackInfo.payload.artwork {
                    self?.artwork = originalArtwork.thumbnail(maxSize: NotchConstants.artworkThumbnailSize)
                } else {
                    self?.artwork = nil
                }
                
                self?.isPlaying = trackInfo.payload.isPlaying ?? false
                
                // Duration & elapsed from MediaRemoteAdapter
                if let durationMicros = trackInfo.payload.durationMicros {
                    self?.trackDuration = durationMicros / 1_000_000
                }
               
            }
        }
        
        mediaController.onPlaybackTimeUpdate = { [weak self] elapsedTime in
            DispatchQueue.main.async {
                self?.trackElapsed = elapsedTime
            }
        }
        
        mediaController.onListenerTerminated = { print("MediaRemoteAdapter listener process was terminated.") }
        mediaController.startListening()
        updateSystemVolume()
    }
    
    deinit {
        mediaController.stopListening()
    }

    func playPause() { mediaController.togglePlayPause() }
    func nextTrack() { mediaController.nextTrack() }
    func previousTrack() { mediaController.previousTrack() }
    func setTime(seconds: Double) {
        let clamped = max(0, min(seconds, trackDuration > 0 ? trackDuration : seconds))
        mediaController.setTime(seconds: clamped)
        DispatchQueue.main.async {
            self.trackElapsed = clamped
        }
    }
    
    func setVolume(_ newValue: Float) {
        _ = executeAppleScript(script: "set volume output volume \(newValue * 100)")
    }
    
    func updateSystemVolume() {
        if let result = executeAppleScript(script: "output volume of (get volume settings)"),
           let volString = result.stringValue,
           let vol = Float(volString) {
            DispatchQueue.main.async { self.volume = vol / 100.0 }
        }
    }

    func toggleMute() {
        let script = """
        set vol to get volume settings
        if output muted of vol then
            set volume without output muted
        else
            set volume with output muted
        end if
        """
        if executeAppleScript(script: script) != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.updateSystemVolume() }
        }
    }
    
    var trackProgress: Double {
        guard trackDuration > 0 else { return 0 }
        return min(trackElapsed / trackDuration, 1.0)
    }
    
    var elapsedTimeString: String {
        formatTime(trackElapsed)
    }
    
    var remainingTimeString: String {
        let remaining = max(trackDuration - trackElapsed, 0)
        return "-\(formatTime(remaining))"
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    @discardableResult
    private func executeAppleScript(script: String) -> NSAppleEventDescriptor? {
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            if let err = error { print("AppleScript Error: \(err)"); return nil }
            return result
        }
        return nil
    }
}
