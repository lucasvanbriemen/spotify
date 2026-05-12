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
    
    func playSong(song: Song) {
        let url = URL(string: "\(Secrets.base_url)get-mp3/" + song.mp3Url!)

        let playerItem = AVPlayerItem(url: url!)
        player = AVPlayer(playerItem: playerItem)
        currentlyPlaying = song
        togglePlayPause(forceState: true)
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
    }
    
    func sncyNowPlayingInfo() {
        guard let song = self.currentlyPlaying else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: song.name,
            MPMediaItemPropertyArtist: song.artist ?? "Unknown Artist",
            MPNowPlayingInfoPropertyPlaybackRate: self.isPlaying ? 1.0 : 0.0
        ]
    }
}
