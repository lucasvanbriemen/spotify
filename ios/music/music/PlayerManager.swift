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
}
