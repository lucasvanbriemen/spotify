import Foundation
import AVFoundation

@Observable
class PlayerManager {   
    static var currentlyPlaying: Song?
    static var isPlaying: Bool = false
    static var playingPlaylistId: Int? = nil
    
    static var player: AVPlayer?
    
    static public func isCurrentlyPlayingPlaylist(playlistId: Int?) -> Bool {
        return self.isPlaying && self.playingPlaylistId == playlistId
    }
}
