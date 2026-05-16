import Foundation
import AVFoundation
import MediaPlayer
#if os(macOS)
import AppKit
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
    private var preloadedSong: Song?
    private var preloadedPlayerItem: AVPlayerItem?
    private var preloader: AVPlayer?
    private var preloadedArtworkSongIsrc: String?
    #if os(macOS)
    private var preloadedArtworkImage: NSImage?
    #else
    private var preloadedArtworkImage: UIImage?
    #endif

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
        let newPlayer: AVPlayer
        if let preloaded = preloader, preloadedSong?.isrc == song.isrc {
            newPlayer = preloaded
            preloader = nil
            preloadedPlayerItem = nil
            preloadedSong = nil
        } else {
            let url = URL(string: "\(Secrets.base_url)get-mp3/\(song.isrc)")
            let headers = ["Authorization": "Bearer \(Secrets.api_key)"]
            let asset = AVURLAsset(url: url!, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            let playerItem = AVPlayerItem(asset: asset)
            newPlayer = AVPlayer(playerItem: playerItem)
        }

        if timeObserverToken != nil {
            player?.removeTimeObserver(timeObserverToken!)
        }
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)

        player = newPlayer
        currentlyPlaying = song
        togglePlayPause(forceState: true)

        timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: CMTimeMake(value: 1, timescale: 1), queue: .main, using: { [weak self] time in
            if self?.isSeeking == true {
                return
            }
            self?.timeIntoSong = CMTimeGetSeconds(time)
            self?.updateNowPlayingProgress()
        })
        if let currentItem = newPlayer.currentItem {
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: currentItem, queue: .main) { [weak self] _ in
                self?.playNextSong()
            }
        }

        prefetchNextSong()
    }

    private func prefetchNextSong() {
        let nextSong = queue.first

        if preloadedSong?.isrc == nextSong?.isrc {
            return
        }

        preloader?.pause()
        preloader?.replaceCurrentItem(with: nil)
        preloader = nil
        preloadedPlayerItem = nil
        preloadedSong = nil
        preloadedArtworkSongIsrc = nil
        preloadedArtworkImage = nil

        guard let song = nextSong else { return }

        guard let url = URL(string: "\(Secrets.base_url)get-mp3/\(song.isrc)") else { return }
        let headers = ["Authorization": "Bearer \(Secrets.api_key)"]
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        preloadedSong = song
        preloadedPlayerItem = item
        preloader = AVPlayer(playerItem: item)
        preloader?.automaticallyWaitsToMinimizeStalling = false

        guard let imageUrlString = song.imageUrl, let imageUrl = URL(string: imageUrlString) else { return }
        URLSession.shared.dataTask(with: imageUrl) { [weak self] data, _, _ in
            guard let data = data else { return }
            #if os(macOS)
                guard let image = NSImage(data: data) else { return }
            #else
                guard let image = UIImage(data: data) else { return }
            #endif
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.currentlyPlaying?.isrc == song.isrc {
                    var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    current[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = current
                    return
                }
                guard self.preloadedSong?.isrc == song.isrc else { return }
                self.preloadedArtworkSongIsrc = song.isrc
                self.preloadedArtworkImage = image
            }
        }.resume()
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

        if preloadedArtworkSongIsrc == song.isrc, let image = preloadedArtworkImage {
            var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            current[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = current
            preloadedArtworkSongIsrc = nil
            preloadedArtworkImage = nil
            return
        }

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
        prefetchNextSong()
    }
}
