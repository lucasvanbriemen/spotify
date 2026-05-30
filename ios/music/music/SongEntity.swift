import AppIntents

struct SongEntity: AppEntity, Identifiable {
    var id: String { isrc }
    var isrc: String
    var title: String
    var artist: String?
    var album: String?
    var duration: Int
    var imageUrl: String?

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Song"
    static var defaultQuery = SongEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: artist.map { "\($0)" })
    }

    init(song: Song) {
        self.isrc = song.isrc
        self.title = song.title
        self.artist = song.artist
        self.album = song.album
        self.duration = song.duration
        self.imageUrl = song.imageUrl
    }

    /// Rebuilds a `Song` model so it can be handed to `PlayerManager`.
    func toSong() -> Song {
        Song(isrc: isrc, title: title, duration: duration, imageUrl: imageUrl, artist: artist, album: album)
    }
}

struct SongEntityQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SongEntity] {
        []
    }

    func entities(matching string: String) async throws -> [SongEntity] {
        let query = string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let results: SearchResults? = await ServerApi.get(endpoint: "search?q=\(query)")
        return (results?.songs ?? []).map { SongEntity(song: $0) }
    }
}
