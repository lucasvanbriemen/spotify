#if !os(watchOS)
import AppIntents

/// Intents backing the widget's playback buttons. `AudioPlaybackIntent` makes
/// the system run `perform()` inside the main app's process (launching it in
/// the background if needed), so the copies compiled into the widget extension
/// never execute — only the MUSIC_APP build does. That is why the bodies are
/// compiled out everywhere else.
struct TogglePlayPauseIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play or Pause"
    static var description = IntentDescription("Toggles playback of the current song.")

    @MainActor
    func perform() async throws -> some IntentResult {
        #if MUSIC_APP
        PlayerManager.shared.togglePlayPause()
        #endif
        return .result()
    }
}

struct NextSongIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Next Song"
    static var description = IntentDescription("Skips to the next song in the queue.")

    @MainActor
    func perform() async throws -> some IntentResult {
        #if MUSIC_APP
        PlayerManager.shared.playNextSong()
        #endif
        return .result()
    }
}

struct PreviousSongIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Previous Song"
    static var description = IntentDescription("Goes back to the previous song.")

    @MainActor
    func perform() async throws -> some IntentResult {
        #if MUSIC_APP
        PlayerManager.shared.playPreviousSong()
        #endif
        return .result()
    }
}
#endif
