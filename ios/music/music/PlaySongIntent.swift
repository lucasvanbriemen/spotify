import AppIntents

/// "Play <song> in Music" — plays a song from the user's playlists. Scoped
/// entirely to PlaylistLibrary: nothing outside your playlists is reachable, and
/// there is no fallback to the global search endpoint.
///
/// Conforming to `AudioPlaybackIntent` lets Siri start playback in the background
/// (e.g. while the phone is locked) without launching the UI.
struct PlaySongIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play a Song"
    static var description = IntentDescription("Play a song from your playlists.")

    @Parameter(title: "Song", requestValueDialog: "What do you want to play?")
    var song: SongEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let match = await PlaylistLibrary.shared.song(withISRC: song.id) else {
            return .result(dialog: "I couldn't find \(song.title) in your playlists.")
        }

        PlayerManager.shared.playSong(song: match)
        return .result(dialog: "Playing \(match.title).")
    }
}
