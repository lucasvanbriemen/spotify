import Foundation

struct Stats: Codable {
    var totalPlays: Int
    var uniqueSongs: Int
    var totalSecondsPlayed: Int
    var topSongs: [TopSong]

    enum CodingKeys: String, CodingKey {
        case totalPlays = "total_plays"
        case uniqueSongs = "unique_songs"
        case totalSecondsPlayed = "total_seconds_played"
        case topSongs = "top_songs"
    }
}

struct TopSong: Codable, Identifiable {
    var isrc: String
    var title: String
    var artist: String
    var imageUrl: String?
    var playCount: Int
    var secondsPlayed: Int

    var id: String { isrc }

    enum CodingKeys: String, CodingKey {
        case isrc, title, artist
        case imageUrl = "image_url"
        case playCount = "play_count"
        case secondsPlayed = "seconds_played"
    }
}

struct RecordedPlay: Codable {
    var id: Int
}
