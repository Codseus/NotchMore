import AppKit
import Foundation
import MediaRemoteAdapter
import SwiftUI

class MediaManager: ObservableObject {
    @Published var currentTrackTitle: String = "Not Playing"
    @Published var currentTrackArtist: String = "No media detected"
    @Published var artwork: NSImage?
    @Published var sourceIcon: NSImage?
    @Published var sourceName: String = "Media"
    @Published var isPlaying: Bool = false
    @Published var volume: Float = 0.5
    @Published var trackDuration: Double = 0
    @Published var trackElapsed: Double = 0

    private let mediaController = MediaController()
    private var artworkCache: [String: NSImage] = [:]
    private var artworkCacheOrder: [String] = []
    private var lastArtworkKey: String?
    private let maxArtworkCacheItems = 8

    init() {
        mediaController.onTrackInfoReceived = { [weak self] trackInfo in
            DispatchQueue.main.async {
                self?.handle(trackInfo)
            }
        }

        mediaController.onPlaybackTimeUpdate = { [weak self] elapsedTime in
            DispatchQueue.main.async {
                self?.handlePlaybackTimeUpdate(elapsedTime)
            }
        }

        mediaController.onListenerTerminated = {
            print("MediaRemoteAdapter listener process was terminated.")
        }
        mediaController.startListening()
        updateSystemVolume()
    }

    deinit {
        mediaController.stopListening()
    }

    func playPause() {
        mediaController.togglePlayPause()
    }

    func nextTrack() {
        mediaController.nextTrack()
    }

    func previousTrack() {
        mediaController.previousTrack()
    }

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
            let vol = Float(volString)
        {
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

    private func handle(_ trackInfo: TrackInfo) {
        let title = trackInfo.payload.title ?? "Unknown Title"
        let artist = trackInfo.payload.artist ?? "Unknown Artist"
        let album = trackInfo.payload.album ?? ""
        let isPlaying = trackInfo.payload.isPlaying ?? false
        let bundleIdentifier = trackInfo.payload.bundleIdentifier
        let appName = trackInfo.payload.applicationName ?? appName(for: bundleIdentifier) ?? "Media"
        let sourceID = bundleIdentifier ?? appName
        let trackIdentity = [sourceID, title, artist, album].joined(separator: "\u{1f}")
        let fallbackTrackIdentity = [sourceID, title, artist].joined(separator: "\u{1f}")

        let thumbnail: NSImage?
        if isNoMediaUpdate(title: title, artist: artist, isPlaying: isPlaying) {
            thumbnail = nil
            lastArtworkKey = nil
        } else if let originalArtwork = artworkImage(from: trackInfo) {
            thumbnail = originalArtwork.thumbnail(maxSize: NotchConstants.artworkThumbnailSize)
            if let thumbnail {
                cacheArtwork(thumbnail, for: trackIdentity)
                cacheArtwork(thumbnail, for: fallbackTrackIdentity)
                lastArtworkKey = fallbackTrackIdentity
            }
        } else if let cachedArtwork = artworkCache[trackIdentity] {
            thumbnail = cachedArtwork
            lastArtworkKey = fallbackTrackIdentity
        } else if let cachedArtwork = artworkCache[fallbackTrackIdentity] {
            thumbnail = cachedArtwork
            lastArtworkKey = fallbackTrackIdentity
        } else if shouldRetainCurrentArtwork(for: fallbackTrackIdentity, title: title, artist: artist, sourceName: appName) {
            thumbnail = artwork
        } else {
            thumbnail = nil
        }

        let duration = (trackInfo.payload.durationMicros ?? 0) / 1_000_000
        let elapsed = (trackInfo.payload.elapsedTimeMicros ?? 0) / 1_000_000

        currentTrackTitle = title
        currentTrackArtist = artist
        artwork = thumbnail
        sourceIcon = appIcon(for: bundleIdentifier)
        sourceName = appName
        self.isPlaying = isPlaying
        trackDuration = duration
        trackElapsed = elapsed
    }

    private func handlePlaybackTimeUpdate(_ elapsedTime: TimeInterval) {
        trackElapsed = elapsedTime
    }


    private func artworkImage(from trackInfo: TrackInfo) -> NSImage? {
        if let artwork = trackInfo.payload.artwork {
            return artwork.hasRenderableImage ? artwork : nil
        }

        guard let base64 = trackInfo.payload.artworkDataBase64,
            let data = Data(base64Encoded: base64)
        else { return nil }

        guard let image = NSImage(data: data), image.hasRenderableImage else { return nil }
        return image
    }

    private func appIcon(for bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier else { return nil }

        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) {
            return app.icon
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    private func appName(for bundleIdentifier: String?) -> String? {
        guard let bundleIdentifier else { return nil }

        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) {
            return app.localizedName
        }

        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)?
            .deletingPathExtension().lastPathComponent
    }

    private func cacheArtwork(_ artwork: NSImage, for trackIdentity: String) {
        artworkCache[trackIdentity] = artwork
        artworkCacheOrder.removeAll { $0 == trackIdentity }
        artworkCacheOrder.append(trackIdentity)

        while artworkCacheOrder.count > maxArtworkCacheItems {
            let removedIdentity = artworkCacheOrder.removeFirst()
            artworkCache.removeValue(forKey: removedIdentity)
        }
    }

    private func shouldRetainCurrentArtwork(
        for artworkKey: String,
        title: String,
        artist: String,
        sourceName: String
    ) -> Bool {
        guard artwork != nil else { return false }

        return lastArtworkKey == artworkKey
            || (currentTrackTitle == title
                && currentTrackArtist == artist
                && self.sourceName == sourceName)
    }

    private func isNoMediaUpdate(title: String, artist: String, isPlaying: Bool) -> Bool {
        !isPlaying && title == "Not Playing" && artist == "No media detected"
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
            if let err = error {
                print("AppleScript Error: \(err)")
                return nil
            }
            return result
        }
        return nil
    }
}
