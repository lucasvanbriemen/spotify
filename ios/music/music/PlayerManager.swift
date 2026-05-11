import Foundation
import AVFoundation

@Observable
class PlayerManager {
    static let shared = PlayerManager()
    private init() {}

    var player: AVPlayer?

    var currentlyPlaying: Song?
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
        togglePlayPause(forceState: true)
    }
}
