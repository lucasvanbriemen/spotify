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
    var id: Int
    var title: String
    var duration: Int
    var fileId: String?
    var imageUrl: String?
    var artist: String?
    var album: String?
    var isInPlaylistMap: [String: PlaylistEntry]?

    enum CodingKeys: String, CodingKey {
        case id, title, artist, album, duration
        case fileId = "file_id"
        case imageUrl = "image_url"
        case isInPlaylistMap = "is_in_playlist_map"
    }
}
