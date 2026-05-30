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

    init(isrc: String = "", title: String = "", duration: Int = 0, imageUrl: String? = nil, artist: String? = nil, album: String? = nil) {
        self.isrc = isrc
        self.title = title
        self.duration = duration
        self.imageUrl = imageUrl
        self.artist = artist
        self.album = album
    }
}

struct SearchResults: Codable {
    var songs: [Song]
    var playlists: [Playlist]
}
