import Foundation
import AVFoundation
import MediaPlayer
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Observable
class PlayerManager {
    static let shared = PlayerManager()
    private init() {
        setUpBackgroundPlayback()
        setUpExternalCommands()
    }

    var player: AVPlayer?

    var currentlyPlaying: Song? {
        didSet {
            sncyNowPlayingInfo()
        }
    }
    var isPlaying: Bool = false
    var playingPlaylistId: String? = nil
    var hasSheetOpen: Bool = false
    var timeIntoSong: Double = 0
    var isSeeking: Bool = false
    var shouldShuffle: Bool = true
    var shouldRepeat: Bool = false
    private var timeObserverToken: Any? = nil
    private var endObserver: NSObjectProtocol?
    var queue: [Song] = []
    var pastQueue: [Song] = []
    var nonShuffledQueue: [Song] = []

    func isCurrentlyPlayingPlaylist(playlistId: String?) -> Bool {
        return self.isPlaying && self.playingPlaylistId == playlistId
    }
    
    func togglePlayPause(forceState: Bool? = nil) {
        if forceState == nil {
            isPlaying.toggle()
        } else {
            isPlaying = forceState!
        }
        
        if isPlaying {
            player?.play()
        } else {
            player?.pause()
        }
    }

    func playPlaylist(playlist: Playlist, atIndex: Int? = nil) {
        playingPlaylistId = playlist.id

        queue = []
        pastQueue = []
        let songs = playlist.songs ?? []
        nonShuffledQueue = songs

        let index = atIndex ?? 0

        for (loopingSongIndex, song) in songs.enumerated() {
            if index <= loopingSongIndex {
                queue.append(song)
            } else {
                pastQueue.append(song)
            }
        }

        if shouldShuffle {
            queue.shuffle()
            pastQueue.shuffle()
        }

        if let atIndex = atIndex {
            let song = songs[atIndex]
            queue.removeAll { $0.id == song.id }
            playSong(song: song)
        } else {
            playSong(song: queue.removeFirst())
        }
    }
    
    func playSong(song: Song) {
        let allowed = CharacterSet.urlQueryAllowed
        let title = song.title.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let artist = (song.artist ?? "").addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let urlString = "\(Secrets.base_url)get-mp3/\(song.isrc)?title=\(title)&artist=\(artist)"

        guard let url = URL(string: urlString) else {
            print("playSong: failed to build URL from \(urlString)")
            return
        }
        print("playSong: loading \(url)")

        if timeObserverToken != nil {
            player?.removeTimeObserver(timeObserverToken!)
        }
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "User-Agent": "music-app/1.0",
                "Accept": "audio/mpeg, audio/*;q=0.9, */*;q=0.1",
                "Authorization": "Bearer \(Secrets.api_key)"
            ]
        ])
        let playerItem = AVPlayerItem(asset: asset)
        NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: playerItem, queue: .main) { note in
            let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey]
            print("playSong: AVPlayerItem failed to play to end — \(String(describing: err))")
        }
        NotificationCenter.default.addObserver(forName: .AVPlayerItemNewErrorLogEntry, object: playerItem, queue: .main) { _ in
            if let last = playerItem.errorLog()?.events.last {
                print("playSong: AVPlayerItem error log — \(last.errorComment ?? "(no comment)") status=\(last.errorStatusCode) domain=\(last.errorDomain)")
            }
        }
        Task {
            do {
                let isPlayable = try await asset.load(.isPlayable)
                print("playSong: isPlayable=\(isPlayable)")
                if !isPlayable {
                    let tracks = try await asset.load(.tracks)
                    print("playSong: tracks=\(tracks.count) types=\(tracks.map { $0.mediaType.rawValue })")
                }
            } catch {
                print("playSong: asset.load failed — \(error)")
            }
        }
        player = AVPlayer(playerItem: playerItem)
        currentlyPlaying = song
        togglePlayPause(forceState: true)

        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: CMTimeMake(value: 1, timescale: 1), queue: .main, using: { [weak self] time in
            if self?.isSeeking == true {
                return
            }
            self?.timeIntoSong = CMTimeGetSeconds(time)
            self?.updateNowPlayingProgress()
        })
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [weak self] _ in
            self?.playNextSong()
        }
    }
    
    func setUpBackgroundPlayback() {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .moviePlayback)
            try audioSession.setActive(true)
        } catch {
            print("Failed to set the audio session configuration")
        }
        #endif
    }
    
    func setUpExternalCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { _ in
            self.togglePlayPause(forceState: true)
            return .success
        }

        commandCenter.pauseCommand.addTarget { _ in
            self.togglePlayPause(forceState: false)
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let time = CMTime(seconds: event.positionTime, preferredTimescale: 600)
            self?.player?.seek(to: time)
            return .success
        }
        
        commandCenter.nextTrackCommand.addTarget { _ in
            self.playNextSong()
            return .success
        }
        
        commandCenter.previousTrackCommand.addTarget { _ in
            self.playPreviousSong()
            return .success

        }

    }
    
    func sncyNowPlayingInfo() {
        guard let song = self.currentlyPlaying else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        let info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist ?? "Unknown Artist",
            MPNowPlayingInfoPropertyPlaybackRate: self.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: self.timeIntoSong,
            MPMediaItemPropertyPlaybackDuration: CMTimeGetSeconds(player?.currentItem?.duration ?? .indefinite)
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        guard let urlString = song.imageUrl, let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else { return }
            #if os(macOS)
            guard let image = NSImage(data: data) else { return }
            #else
            guard let image = UIImage(data: data) else { return }
            #endif
            DispatchQueue.main.async {
                guard self.currentlyPlaying?.id == song.id else { return }
                var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                current[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                MPNowPlayingInfoCenter.default().nowPlayingInfo = current
            }
        }.resume()
    }

    func updateNowPlayingProgress() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = self.timeIntoSong
        info[MPNowPlayingInfoPropertyPlaybackRate] = self.isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    func playNextSong() {
        
        if shouldRepeat {
            timeIntoSong = 0
            player?.seek(to: .zero)
            togglePlayPause(forceState: true)
            return
        }
        
        if let current = currentlyPlaying {
            pastQueue.append(current)
        }
        
        if (!queue.isEmpty) {
            playSong(song: queue.removeFirst())
        } else {
            togglePlayPause(forceState: false)
        }
    }
    
    func playPreviousSong() {
        if shouldRepeat {
            timeIntoSong = 0
            player?.seek(to: .zero)
            togglePlayPause(forceState: true)
            return
        }
        
        if self.timeIntoSong < 5 && self.pastQueue.count > 0 {
            if let current = currentlyPlaying {
                queue.insert(current, at: 0)
            }
            if let previous = pastQueue.popLast() {
                playSong(song: previous)
            }
        }
        
        self.player?.seek(to: .zero)
        
    }
    
    func applySuffle() {
        if shouldShuffle {
            queue.shuffle()
        } else if let current = currentlyPlaying {
            queue = []
            pastQueue = []
            var reachedCurrent = false
            for nonShuffeldSong in nonShuffledQueue {
                if nonShuffeldSong.id == current.id {
                    reachedCurrent = true
                    continue
                }
                if reachedCurrent {
                    queue.append(nonShuffeldSong)
                } else {
                    pastQueue.append(nonShuffeldSong)
                }
            }
        }
    }
}
