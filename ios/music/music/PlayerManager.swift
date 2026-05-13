import Foundation
import AVFoundation
import MediaPlayer

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
    var playingPlaylistId: Int? = nil
    private var timeIntoSong: Double = 0
    private var timeObserverToken: Any? = nil
    private var endObserver: NSObjectProtocol?
    var queue: [Song] = []
    var pastQueue: [Song] = []

    func isCurrentlyPlayingPlaylist(playlistId: Int?) -> Bool {
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

    func playPlaylist(playlist: Playlist) {
        playingPlaylistId = playlist.id
        
        if let firstSong = playlist.songs?.first {
            playSong(song: firstSong)
        }
        
        queue = playlist.songs ?? []
        
        // Remove the first item, as thats currently playing
        queue.remove(at: 0)
    }
    
    func playSong(song: Song) {
        let url = URL(string: "\(Secrets.base_url)get-mp3/" + song.fileId!)

        if timeObserverToken != nil {
            player?.removeTimeObserver(timeObserverToken!)
        }
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        let playerItem = AVPlayerItem(url: url!)
        player = AVPlayer(playerItem: playerItem)
        currentlyPlaying = song
        togglePlayPause(forceState: true)

        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: CMTimeMake(value: 1, timescale: 1), queue: .main, using: { [weak self] time in
            self?.timeIntoSong = CMTimeGetSeconds(time)
            self?.sncyNowPlayingInfo()
        })
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [weak self] _ in
            self?.playNextSong()
        }
    }
    
    func setUpBackgroundPlayback() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .moviePlayback)
            try audioSession.setActive(true)
        } catch {
            print("Failed to set the audio session configuration")
        }
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
            if self.timeIntoSong < 5 && self.pastQueue.count > 0 {
                self.playPreviousSong()
                return .success
            }
            
            self.player?.seek(to: .zero)
            return .success
        }

    }
    
    func sncyNowPlayingInfo() {
        guard let song = self.currentlyPlaying else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist ?? "Unknown Artist",
            MPNowPlayingInfoPropertyPlaybackRate: self.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: self.timeIntoSong,
            MPMediaItemPropertyPlaybackDuration: CMTimeGetSeconds(player?.currentItem?.duration ?? .indefinite)
        ]
    }
    
    func playNextSong() {
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
        if let current = currentlyPlaying {
            queue.insert(current, at: 0)
        }
        if let previous = pastQueue.popLast() {
            playSong(song: previous)
        }
    }
}
