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
        self.title = Self.sayableTitle(song.title)
        self.artist = song.artist
    }

    /// Siri matches what the user says against the donated title, so the
    /// donated form must be sayable. Catalogue titles carry extras nobody
    /// speaks — "(2008 Remaster)", "[Live]", "- Radio Edit" — which would make
    /// Siri reject the plain spoken title, so they are stripped here.
    static func sayableTitle(_ title: String) -> String {
        var clean = title.replacingOccurrences(
            of: #"\s*[\(\[][^\)\]]*[\)\]]"#,
            with: "",
            options: .regularExpression
        )
        if let qualifier = clean.range(of: #"\s+-\s.*$"#, options: .regularExpression) {
            clean.removeSubrange(qualifier)
        }
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? title : clean
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
    /// Deduped by spoken form like suggestedEntities(): different releases of
    /// the same song would otherwise show up as identical twins in Siri's
    /// "Which one?" prompt. songs(matching:) sorts best-match-first, so keeping
    /// the first occurrence keeps the release closest to what was spoken.
    func entities(matching string: String) async throws -> [SongEntity] {
        var seen = Set<String>()
        return await PlaylistLibrary.shared.songs(matching: string).compactMap { song in
            let entity = SongEntity(song: song)
            let spokenForm = "\(entity.title.lowercased())|\(entity.artist?.lowercased() ?? "")"
            guard seen.insert(spokenForm).inserted else { return nil }
            return entity
        }
    }

    /// Vocabulary/suggestions surfaced to Siri and shown in the Shortcuts app.
    /// Every playlist song is donated — Siri can only recognise spoken values
    /// from this list, so capping it makes the rest of the library unsayable.
    /// Different releases of the same song collapse to one entry per spoken
    /// form ("Thriller" and "Thriller (Live)" would otherwise be identical
    /// twins in Siri's disambiguation prompt), keeping the release whose title
    /// is closest to the spoken form — the plain studio cut, not the live take.
    func suggestedEntities() async throws -> [SongEntity] {
        let songs = await PlaylistLibrary.shared.songs()

        var best: [String: (song: Song, order: Int)] = [:]
        for (order, song) in songs.enumerated() {
            let entity = SongEntity(song: song)
            let spokenForm = "\(entity.title.lowercased())|\(entity.artist?.lowercased() ?? "")"
            if let current = best[spokenForm] {
                if song.title.count < current.song.title.count {
                    best[spokenForm] = (song, current.order)
                }
            } else {
                best[spokenForm] = (song, order)
            }
        }

        return best.values.sorted { $0.order < $1.order }.map { SongEntity(song: $0.song) }
    }
}
