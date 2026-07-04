import AppIntents

/// A song from the user's playlists, exposed to Siri and the Shortcuts app.
/// `id` is the ISRC, which is also what PlayerManager uses to stream the file.
struct SongEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Song")
    static var defaultQuery = SongEntityQuery()

    let id: String
    let title: String
    let artist: String?

    var displayRepresentation: DisplayRepresentation {
        if let artist, !artist.isEmpty {
            return DisplayRepresentation(title: "\(title)", subtitle: "\(artist)")
        }
        return DisplayRepresentation(title: "\(title)")
    }

    init(song: Song) {
        self.id = song.isrc
        self.title = song.title
        self.artist = song.artist
    }
}

/// Resolves SongEntities strictly from PlaylistLibrary — this is what keeps Siri
/// scoped to songs that are already in the user's playlists.
struct SongEntityQuery: EntityStringQuery {
    /// Re-hydrate entities by id (ISRC), e.g. when Siri already has a selection.
    func entities(for identifiers: [SongEntity.ID]) async throws -> [SongEntity] {
        let ids = Set(identifiers)
        return await PlaylistLibrary.shared.songs()
            .filter { ids.contains($0.isrc) }
            .map(SongEntity.init)
    }

    /// Match the spoken phrase against playlist songs (title / artist).
    func entities(matching string: String) async throws -> [SongEntity] {
        await PlaylistLibrary.shared.songs(matching: string).map(SongEntity.init)
    }

    /// Vocabulary/suggestions surfaced to Siri and shown in the Shortcuts app.
    func suggestedEntities() async throws -> [SongEntity] {
        await PlaylistLibrary.shared.songs().prefix(100).map(SongEntity.init)
    }
}
