import Foundation

@Observable
class PlayerData {
    static let shared = PlayerData()
    var currentlyPlaying: Song?
    private init() {}
}
