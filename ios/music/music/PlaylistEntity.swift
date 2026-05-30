import AppIntents
import os

private let entityLogger = Logger(subsystem: "nl.ltvb.music", category: "SiriEntity")

struct PlaylistEntity: AppEntity, Identifiable {
    var id: String
    var name: String
    var author: String?

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Playlist"
    static var defaultQuery = PlaylistEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: author.map { "\($0)" })
    }

    init(id: String, name: String, author: String? = nil) {
        self.id = id
        self.name = name
        self.author = author
    }

    init(playlist: Playlist) {
        self.id = playlist.id
        self.name = playlist.name
        self.author = playlist.author
    }
}

struct PlaylistEntityQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PlaylistEntity] {
        let playlists: [Playlist] = await ServerApi.get(endpoint: "playlists") ?? []
        return playlists
            .filter { identifiers.contains($0.id) }
            .map { PlaylistEntity(playlist: $0) }
    }

    func suggestedEntities() async throws -> [PlaylistEntity] {
        let playlists: [Playlist] = await ServerApi.get(endpoint: "playlists") ?? []
        entityLogger.log("PlaylistEntityQuery.suggestedEntities count=\(playlists.count, privacy: .public)")
        return playlists.map { PlaylistEntity(playlist: $0) }
    }

    func entities(matching string: String) async throws -> [PlaylistEntity] {
        entityLogger.log("PlaylistEntityQuery.entities(matching:) string=\(string, privacy: .public)")
        let query = string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let results: SearchResults? = await ServerApi.get(endpoint: "search?q=\(query)")
        let matches = (results?.playlists ?? []).map { PlaylistEntity(playlist: $0) }
        entityLogger.log("PlaylistEntityQuery.entities(matching:) matches=\(matches.count, privacy: .public)")
        return matches
    }
}
