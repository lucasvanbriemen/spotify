import AppIntents
import os

struct SearchMusicIntent: AudioPlaybackIntent {
    static let logger = Logger(subsystem: "nl.ltvb.music", category: "SiriIntent")

    static var title: LocalizedStringResource = "Listen to a Song"
    static var description = IntentDescription("Search for a song and play the best match.")

    @Parameter(title: "Song", requestValueDialog: "What do you want to listen to?")
    var searchTerm: String

    static var parameterSummary: some ParameterSummary {
        Summary("Listen to \(\.$searchTerm)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let query = searchTerm
        Self.logger.log("SearchMusicIntent.perform START term=\(query, privacy: .public)")

        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let results: SearchResults? = await ServerApi.get(endpoint: "search?q=\(encoded)")
        let count = results?.songs.count ?? -1
        Self.logger.log("SearchMusicIntent search returned songs=\(count, privacy: .public)")

        guard let first = results?.songs.first else {
            return .result(dialog: "Debug: search for \(query) returned \(count) songs.")
        }

        PlayerManager.shared.playSong(song: first)
        Self.logger.log("SearchMusicIntent playSong title=\(first.title, privacy: .public)")
        return .result(dialog: "Playing \(first.title).")
    }
}
