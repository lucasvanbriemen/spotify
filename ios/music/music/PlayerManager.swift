import Foundation
import AVFoundation

@Observable
class PlayerManager {
    static let shared = PlayerManager()
    private init() {}

    var currentlyPlaying: Song?
    var isPlaying: Bool = false
    var playingPlaylistId: Int? = nil

    var player: AVPlayer?

    func isCurrentlyPlayingPlaylist(playlistId: Int?) -> Bool {
        return self.isPlaying && self.playingPlaylistId == playlistId
    }
}
