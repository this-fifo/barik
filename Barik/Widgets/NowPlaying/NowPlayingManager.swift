import AppKit
import Combine
import Foundation

// MARK: - Playback State

/// Represents the current playback state.
enum PlaybackState: String {
    case playing, paused, stopped
}

// MARK: - Now Playing Song Model

/// A model representing the currently playing song.
struct NowPlayingSong: Equatable, Identifiable {
    var id: String { title + artist }
    let appName: String
    let state: PlaybackState
    let title: String
    let artist: String
    let albumArtData: Data?  // Base64-decoded artwork data
    let position: Double?
    let duration: Double?  // Duration in seconds

    /// Initializes a song model from media-control JSON output.
    /// - Parameter json: The JSON dictionary from media-control.
    init?(from json: [String: Any]) {
        guard let title = json["title"] as? String,
              let artist = json["artist"] as? String,
              let playing = json["playing"] as? Bool else {
            return nil
        }

        // Get app name from bundle identifier
        if let bundleId = json["bundleIdentifier"] as? String {
            self.appName = bundleId.contains("Music") ? "Music" : "Unknown"
        } else {
            self.appName = "Unknown"
        }

        self.state = playing ? .playing : .paused
        self.title = title
        self.artist = artist

        // Decode base64 artwork data
        if let artworkBase64 = json["artworkData"] as? String,
           let artworkData = Data(base64Encoded: artworkBase64) {
            self.albumArtData = artworkData
        } else {
            self.albumArtData = nil
        }

        // Use elapsedTimeNow if available (from --now flag), otherwise elapsedTime
        self.position = json["elapsedTimeNow"] as? Double ?? json["elapsedTime"] as? Double
        self.duration = json["duration"] as? Double
    }
}

// MARK: - Now Playing Provider

/// Provides functionality to fetch the now playing song and execute playback commands using media-control.
final class NowPlayingProvider {

    /// Returns the current playing song using media-control CLI with --now flag for accurate position.
    static func fetchNowPlaying() -> NowPlayingSong? {
        guard let output = runShellCommand("/opt/homebrew/bin/media-control", args: ["get", "--now"]),
              let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return NowPlayingSong(from: json)
    }

    /// Executes a shell command and returns the output.
    @discardableResult
    static func runShellCommand(_ command: String, args: [String] = []) -> String? {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            print("Shell command error: \(error)")
            return nil
        }
    }

    /// Executes a playback command using media-control.
    static func executeCommand(_ command: String) {
        _ = runShellCommand("/opt/homebrew/bin/media-control", args: [command])
    }

    /// Seeks to a specific position in seconds using AppleScript.
    /// Note: media-control seek doesn't work with Apple Music, so we use AppleScript instead.
    static func seek(to position: Double) {
        let script = "tell application \"Music\" to set player position to \(position)"
        _ = runShellCommand("/usr/bin/osascript", args: ["-e", script])
    }
}

// MARK: - Now Playing Manager

/// An observable manager that periodically updates the now playing song.
final class NowPlayingManager: ObservableObject {
    static let shared = NowPlayingManager()

    @Published private(set) var nowPlaying: NowPlayingSong?
    private var cancellable: AnyCancellable?
    private var sleepWakeObservers: [NSObjectProtocol] = []

    private init() {
        startMonitoring()
        observeSleepWake()
    }

    deinit {
        stopMonitoring()
        removeSleepWakeObservers()
    }

    private func observeSleepWake() {
        let sleepObserver = NotificationCenter.default.addObserver(
            forName: SleepWakeManager.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopMonitoring()
        }

        let wakeObserver = NotificationCenter.default.addObserver(
            forName: SleepWakeManager.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.startMonitoring()
        }

        sleepWakeObservers.append(contentsOf: [sleepObserver, wakeObserver])
    }

    private func removeSleepWakeObservers() {
        sleepWakeObservers.forEach { NotificationCenter.default.removeObserver($0) }
        sleepWakeObservers.removeAll()
    }

    private func startMonitoring() {
        guard cancellable == nil else { return }
        cancellable = Timer.publish(every: 0.3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateNowPlaying()
            }
    }

    private func stopMonitoring() {
        cancellable?.cancel()
        cancellable = nil
    }

    /// Updates the now playing song asynchronously.
    private func updateNowPlaying() {
        DispatchQueue.global(qos: .background).async {
            let song = NowPlayingProvider.fetchNowPlaying()
            DispatchQueue.main.async { [weak self] in
                self?.nowPlaying = song
            }
        }
    }

    /// Skips to the previous track.
    func previousTrack() {
        NowPlayingProvider.executeCommand("previous-track")
    }

    /// Toggles between play and pause.
    func togglePlayPause() {
        NowPlayingProvider.executeCommand("toggle-play-pause")
    }

    /// Skips to the next track.
    func nextTrack() {
        NowPlayingProvider.executeCommand("next-track")
    }

    /// Seeks to a specific position in seconds.
    func seek(to position: Double) {
        NowPlayingProvider.seek(to: position)
    }
}
