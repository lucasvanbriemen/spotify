import Foundation

@Observable
class PlayerData {
    static let shared = PlayerData()
    private init() {}
    
    var currentlyPlaying: Song?
    var isPlaying: Bool = false
}
