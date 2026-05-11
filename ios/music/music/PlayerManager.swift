import Foundation

@Observable
class PlayerManager {   
    static var currentlyPlaying: Song?
    static var isPlaying: Bool = false
    static var playingPlaylistId: Int? = nil
    
    static public  func isCurrentlyPlayingPlaylist(playlistId: Int?) -> Bool {
        return self.isPlaying && self.playingPlaylistId == playlistId
    }
}
