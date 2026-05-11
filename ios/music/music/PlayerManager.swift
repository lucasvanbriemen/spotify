import Foundation

@Observable
class PlayerManager {
    static let shared = PlayerManager()
    private init() {}
    
    var currentlyPlaying: Song?
    var isPlaying: Bool = false
    var playingPlaylistId: Int? = nil
    
    public func isCurrentlyPlayingPlaylist(playlistId: Int?) -> Bool {
        return self.isPlaying && self.playingPlaylistId == playlistId
    }
}
