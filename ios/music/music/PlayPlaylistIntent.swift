import AppIntents
import os

struct PlayPlaylistIntent: AudioPlaybackIntent {
    static let logger = Logger(subsystem: "nl.ltvb.music", category: "SiriIntent")

    static var title: LocalizedStringResource = "Play Playlist"
    static var description = IntentDescription("Play one of your playlists.")

    @Parameter(title: "Playlist")
    var playlist: PlaylistEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$playlist)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        Self.logger.log("PlayPlaylistIntent.perform START id=\(playlist.id, privacy: .public) name=\(playlist.name, privacy: .public)")

        guard let full: Playlist = await ServerApi.get(endpoint: "playlist/\(playlist.id)") else {
            return .result(dialog: "Debug: couldn't fetch playlist \(playlist.name).")
        }

        let count = full.songs?.count ?? 0
        Self.logger.log("PlayPlaylistIntent fetched songs=\(count, privacy: .public)")

        guard count > 0 else {
            return .result(dialog: "Debug: \(playlist.name) has \(count) songs.")
        }

        PlayerManager.shared.playPlaylist(playlist: full)
        return .result(dialog: "Playing \(playlist.name).")
    }
}
