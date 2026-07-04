import Foundation
import AVFoundation
import MediaPlayer
import SwiftUI

/// Watch-side player: a trimmed-down PlayerManager that streams the same
/// server MP3s directly on the watch, so it works without the phone nearby.
/// watchOS only plays long-form audio through Bluetooth headphones, which is
/// why every playback start goes through the async session activation that
/// prompts the user to pick an output route if none is connected.
@Observable
class WatchPlayerManager {
    static let shared = WatchPlayerManager()
    private init() {
        setUpRemoteCommands()
    }

    var player: AVPlayer?
    var currentlyPlaying: Song?
    var isPlaying: Bool = false
    var playingPlaylistId: String? = nil
    var shouldShuffle: Bool = true

    private var queue: [Song] = []
    private var pastQueue: [Song] = []
    private var endObserver: NSObjectProtocol?

    func playPlaylist(_ playlist: Playlist, startingAt song: Song? = nil) {
        var songs = playlist.songs ?? []
        guard !songs.isEmpty else { return }

        playingPlaylistId = playlist.id
        pastQueue = []

        let first: Song
        if let song {
            songs.removeAll { $0.isrc == song.isrc }
            first = song
        } else {
            first = songs.removeFirst()
        }

        if shouldShuffle {
            songs.shuffle()
        }
        queue = songs

        play(first)
    }

    func play(_ song: Song) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        session.activate(options: []) { [weak self] success, _ in
            guard success else { return }
            Task { @MainActor in
                self?.startPlayback(of: song)
            }
        }
    }

    private func startPlayback(of song: Song) {
        guard let url = URL(string: "\(Secrets.base_url)get-mp3/\(song.isrc)") else { return }
        let headers = ["Authorization": "Bearer \(Secrets.api_key)"]
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)

        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        player?.pause()

        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        currentlyPlaying = song
        isPlaying = true
        newPlayer.play()

        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.playNextSong()
            }
        }

        // Ask the server to cache the next few queued songs so skipping ahead
        // never waits on a fresh download, mirroring the phone app.
        for upcoming in queue.prefix(2) {
            ServerApi.warm(endpoint: "get-mp3/\(upcoming.isrc)/prepare")
        }

        syncNowPlayingInfo()
    }

    func togglePlayPause() {
        isPlaying.toggle()
        if isPlaying {
            player?.play()
        } else {
            player?.pause()
        }
        syncNowPlayingInfo()
    }

    func playNextSong() {
        if let current = currentlyPlaying {
            pastQueue.append(current)
        }
        if !queue.isEmpty {
            play(queue.removeFirst())
        } else {
            isPlaying = false
            player?.pause()
        }
    }

    func playPreviousSong() {
        guard !pastQueue.isEmpty else {
            player?.seek(to: .zero)
            return
        }
        if let current = currentlyPlaying {
            queue.insert(current, at: 0)
        }
        play(pastQueue.removeLast())
    }

    private func setUpRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playNextSong() }
            return .success
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPreviousSong() }
            return .success
        }
    }

    private func syncNowPlayingInfo() {
        guard let song = currentlyPlaying else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist ?? "Unknown Artist",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        info[MPMediaItemPropertyPlaybackDuration] = Double(song.duration)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        guard let urlString = song.imageUrl, let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            Task { @MainActor in
                guard self.currentlyPlaying?.isrc == song.isrc else { return }
                var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                current[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                MPNowPlayingInfoCenter.default().nowPlayingInfo = current
            }
        }.resume()
    }
}
