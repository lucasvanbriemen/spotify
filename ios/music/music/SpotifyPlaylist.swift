import Foundation

class SpotifyPlaylist: Codable, Identifiable {
    var id: String
    var name: String
    var description: String?
    var imageUrl: String?
    var owner: String?
    var trackCount: Int?
    var songs: [Song]?

    enum CodingKeys: String, CodingKey {
        case id, name, description, owner, songs
        case imageUrl = "image_url"
        case trackCount = "track_count"
    }
}

struct SearchResults: Codable {
    var tracks: [Song]
    var playlists: [SpotifyPlaylist]
}
