import Foundation

struct PlaylistEntry: Codable {
    var name: String
    var imageUrl: String?
    var contains: Bool

    enum CodingKeys: String, CodingKey {
        case name, contains
        case imageUrl = "image_url"
    }
}

class Song: Codable, Identifiable {
    var isrc: String
    var title: String
    var duration: Int
    var imageUrl: String?
    var artist: String?
    var album: String?
    var isInPlaylistMap: [String: PlaylistEntry]?

    enum CodingKeys: String, CodingKey {
        case isrc, title, artist, album, duration
        case imageUrl = "image_url"
        case isInPlaylistMap = "is_in_playlist_map"
    }
}
