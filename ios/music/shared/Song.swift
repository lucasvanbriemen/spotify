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
    // "song" (or nil, for older payloads/caches) for music, "talk" for radio
    // talk segments (news bulletins etc.) served by the stations feature.
    var kind: String?
    var talkKind: String?
    var isInPlaylistMap: [String: PlaylistEntry]?

    var isTalk: Bool { kind == "talk" }

    enum CodingKeys: String, CodingKey {
        case isrc, title, artist, album, duration, kind
        case talkKind = "talk_kind"
        case imageUrl = "image_url"
        case isInPlaylistMap = "is_in_playlist_map"
    }
}

struct SearchResults: Codable {
    var songs: [Song]
    var playlists: [Playlist]
}
