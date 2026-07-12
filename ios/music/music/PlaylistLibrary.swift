import AppIntents
import Foundation

/// The single source of truth for Siri playback: every song contained in the
/// user's playlists. Siri is intentionally scoped to these songs — we never fall
/// back to the global (iTunes/Deezer) search endpoint, so "Play X in Music" can
/// only ever play something that is already in one of your playlists.
///
/// Latency matters here: Siri background-launches the app and gives an intent
/// only a few seconds before giving up with "I'm having a bit of trouble".
/// The library therefore persists itself to disk and serves stale data
/// immediately while refetching in the background — the network is never on
/// Siri's critical path except on the very first run.
actor PlaylistLibrary {
    static let shared = PlaylistLibrary()

    private var cachedSongs: [Song] = []
    private var lastFetch: Date?
    private var lastAttempt: Date?
    private var refreshTask: Task<[Song], Never>?
    private var triedDiskCache = false
    private let ttl: TimeInterval = 300 // Refetch at most once every 5 minutes.
    private let retryBackoff: TimeInterval = 30 // Pause between failed refetches.

    /// The isrc+title set Siri's vocabulary was last built from, so a refetch
    /// only re-donates App Shortcut parameters when something actually changed.
    private var donatedKey: Set<String>?

    /// All unique songs across the user's playlists, deduplicated by ISRC.
    /// Serves cached (even stale) data immediately and refreshes in the
    /// background; only blocks on the network when there is no cache at all.
    func songs() async -> [Song] {
        if cachedSongs.isEmpty, !triedDiskCache {
            triedDiskCache = true
            if let data = try? Data(contentsOf: Self.cacheURL),
               let songs = try? JSONDecoder().decode([Song].self, from: data) {
                // Deliberately leave lastFetch nil: disk data is usable right
                // away but treated as stale, so a refresh starts below. This
                // snapshot is what the launch-time donation will serve, so it
                // becomes the baseline the refetch compares against.
                cachedSongs = songs
                donatedKey = Self.donationKey(for: songs)
            }
        }

        let isFresh = lastFetch.map { Date().timeIntervalSince($0) < ttl } ?? false
        if isFresh, !cachedSongs.isEmpty { return cachedSongs }

        // After a failed refetch, wait out the backoff instead of hammering
        // the server on every Siri query while the network is down.
        let canAttempt = lastAttempt.map { Date().timeIntervalSince($0) >= retryBackoff } ?? true
        guard canAttempt || refreshTask != nil else { return cachedSongs }

        let refresh = startRefreshIfNeeded()
        if cachedSongs.isEmpty {
            return await refresh.value // First run ever: nothing to serve yet.
        }
        return cachedSongs // Stale-while-revalidate.
    }

    /// Look up a previously-listed song by its ISRC (the SongEntity id).
    func song(withISRC isrc: String) async -> Song? {
        await songs().first { $0.isrc == isrc }
    }

    /// Call after playlist contents change (e.g. a song was added): waits out
    /// any in-flight refresh that may predate the change, then refetches so the
    /// new song becomes sayable through Siri right away.
    func playlistsDidChange() async {
        if let refreshTask { _ = await refreshTask.value }
        lastFetch = nil
        lastAttempt = nil // The data changed for sure — skip any failure backoff.
        _ = await startRefreshIfNeeded().value
    }

    private func startRefreshIfNeeded() -> Task<[Song], Never> {
        if let refreshTask { return refreshTask }
        let task = Task { await self.refetch() }
        refreshTask = task
        return task
    }

    private func refetch() async -> [Song] {
        defer { refreshTask = nil }
        lastAttempt = Date()

        guard let playlists: [Playlist] = await ServerApi.get(endpoint: "playlists") else {
            return cachedSongs // Network hiccup: keep whatever we had rather than wiping it.
        }

        // `playlist/{id}` returns the playlist with its `songs` populated, the
        // same call PlaylistView relies on. Fetched concurrently, but collected
        // in playlist order so ISRC dedup stays deterministic.
        let fetched: [Playlist?] = await withTaskGroup(of: (Int, Playlist?).self) { group in
            for (index, playlist) in playlists.enumerated() {
                group.addTask { (index, await ServerApi.get(endpoint: "playlist/\(playlist.id)")) }
            }
            var results = [Playlist?](repeating: nil, count: playlists.count)
            for await (index, playlist) in group { results[index] = playlist }
            return results
        }

        // A failed playlist fetch means a partial library. Committing it would
        // shrink Siri's vocabulary and overwrite the good on-disk snapshot, so
        // treat the whole refresh as failed: keep serving what we had (lastFetch
        // stays unset, so the next call retries after the backoff).
        if fetched.contains(where: { $0 == nil }) {
            return cachedSongs
        }

        var seen = Set<String>()
        var collected: [Song] = []
        for playlist in fetched {
            for song in playlist?.songs ?? [] where !seen.contains(song.isrc) {
                seen.insert(song.isrc)
                collected.append(song)
            }
        }

        cachedSongs = collected
        lastFetch = Date()
        if let data = try? JSONEncoder().encode(collected) {
            try? data.write(to: Self.cacheURL, options: .atomic)
        }
        donateIfChanged(collected)
        #if os(iOS)
        // Nudges Siri to route bare "play X" requests (no app name) here.
        SiriMediaContext.publish(librarySize: collected.count)
        #endif
        return collected
    }

    /// Siri can only recognise spoken parameter values that have been donated,
    /// so whenever the fetched song set differs from what the vocabulary was
    /// last built from (the disk snapshot served to the launch-time donation,
    /// or a previous refetch) the App Shortcut parameters are re-donated. At
    /// worst this costs one redundant update per launch — a stale vocabulary
    /// costs "Music hasn't added support for that".
    private func donateIfChanged(_ songs: [Song]) {
        let key = Self.donationKey(for: songs)
        guard donatedKey != key else { return }
        donatedKey = key
        MusicShortcuts.updateAppShortcutParameters()
    }

    private static func donationKey(for songs: [Song]) -> Set<String> {
        Set(songs.map { "\($0.isrc)|\($0.title)" })
    }

    private static let cacheURL: URL = {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent("playlist-library.json")
    }()

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
