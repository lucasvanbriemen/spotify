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

    /// Songs matching the spoken search terms. Spoken queries rarely include the
    /// extras catalogue titles carry — "(Remastered 2009)", "(I Just)", "- Radio
    /// Edit" — so a plain substring test fails on them. Instead both sides are
    /// normalized (case/diacritic folded, punctuation and brackets stripped) and
    /// compared word by word: every spoken word must appear somewhere in the
    /// song's title + artist. Words also match across spacing differences, so
    /// "Bittersweet Symphony" finds "Bitter Sweet Symphony".
    func songs(matching query: String) async -> [Song] {
        let needle = Self.searchTokens(in: query)
        guard !needle.isEmpty else { return await songs() }

        let scored: [(song: Song, extras: Int)] = await songs().compactMap { song in
            let haystack = Self.searchTokens(in: "\(song.title) \(song.artist ?? "")")
            guard Self.matches(needle: needle, haystack: haystack) else { return nil }
            return (song, max(0, haystack.count - needle.count))
        }

        // When several songs match, prefer the ones with the least unspoken
        // extra words — "Song" over "Song (Live Extended Remix)".
        return scored.sorted { $0.extras < $1.extras }.map(\.song)
    }

    /// Lowercased alphanumeric words; folding removes accents ("beyonce"
    /// matches "Beyoncé") and the split throws away brackets and punctuation.
    private static func searchTokens(in text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// True when every spoken word occurs in the song's words. Words that don't
    /// match one-to-one are retried against the song's words joined together,
    /// which bridges spacing differences ("bittersweet" vs "bitter sweet").
    private static func matches(needle: [String], haystack: [String]) -> Bool {
        let haystackSet = Set(haystack)
        let unmatched = needle.filter { !haystackSet.contains($0) }
        if unmatched.isEmpty { return true }

        let joined = haystack.joined()
        return unmatched.allSatisfy { joined.contains($0) }
    }
}
