import Foundation

/// The single source of truth for Siri playback: every song contained in the
/// user's playlists. Siri is intentionally scoped to these songs — we never fall
/// back to the global (iTunes/Deezer) search endpoint, so "Play X in Music" can
/// only ever play something that is already in one of your playlists.
actor PlaylistLibrary {
    static let shared = PlaylistLibrary()

    private var cachedSongs: [Song] = []
    private var lastFetch: Date?
    private let ttl: TimeInterval = 300 // Refetch at most once every 5 minutes.

    /// All unique songs across the user's playlists, deduplicated by ISRC.
    func songs() async -> [Song] {
        if let lastFetch, Date().timeIntervalSince(lastFetch) < ttl, !cachedSongs.isEmpty {
            return cachedSongs
        }

        guard let playlists: [Playlist] = await ServerApi.get(endpoint: "playlists") else {
            return cachedSongs // Network hiccup: keep whatever we had rather than wiping it.
        }

        var seen = Set<String>()
        var collected: [Song] = []
        for playlist in playlists {
            // `playlist/{id}` returns the playlist with its `songs` populated,
            // the same call PlaylistView relies on.
            let full: Playlist? = await ServerApi.get(endpoint: "playlist/\(playlist.id)")
            for song in full?.songs ?? [] where !seen.contains(song.isrc) {
                seen.insert(song.isrc)
                collected.append(song)
            }
        }

        cachedSongs = collected
        lastFetch = Date()
        return collected
    }

    /// Look up a previously-listed song by its ISRC (the SongEntity id).
    func song(withISRC isrc: String) async -> Song? {
        await songs().first { $0.isrc == isrc }
    }

    /// Songs whose title or artist contain the spoken search terms. Matching is
    /// case- and diacritic-insensitive so "beyonce" matches "Beyoncé".
    func songs(matching query: String) async -> [Song] {
        let needle = query.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        guard !needle.isEmpty else { return await songs() }
        return await songs().filter { song in
            let haystack = "\(song.title) \(song.artist ?? "")"
                .folding(options: .diacriticInsensitive, locale: .current).lowercased()
            return haystack.contains(needle)
        }
    }
}
