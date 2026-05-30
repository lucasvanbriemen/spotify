import AppIntents
import os

/// Diagnostic: a parameterless playback intent. If this reaches `perform` (Siri
/// speaks "Playing …" / "Debug: …") while the parameterized intents don't, the
/// problem is isolated to Siri's parameter resolution, not the App Shortcut pipeline.
struct PlaySomethingIntent: AudioPlaybackIntent {
    static let logger = Logger(subsystem: "nl.ltvb.music", category: "SiriIntent")

    static var title: LocalizedStringResource = "Surprise Me"
    static var description = IntentDescription("Play the first available playlist (diagnostic).")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        Self.logger.log("PlaySomethingIntent.perform START")

        let playlists: [Playlist] = await ServerApi.get(endpoint: "playlists") ?? []
        Self.logger.log("PlaySomethingIntent playlists=\(playlists.count, privacy: .public)")

        guard let firstId = playlists.first?.id,
              let full: Playlist = await ServerApi.get(endpoint: "playlist/\(firstId)"),
              (full.songs?.isEmpty == false) else {
            return .result(dialog: "Debug: found \(playlists.count) playlists but no playable songs.")
        }

        PlayerManager.shared.playPlaylist(playlist: full)
        return .result(dialog: "Playing \(full.name).")
    }
}
