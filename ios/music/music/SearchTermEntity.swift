import AppIntents
import os

/// A pass-through entity that simply echoes the spoken/typed text. This lets an
/// App Shortcut phrase capture free-form input (e.g. "Play I was made for loving you"),
/// since phrases can only interpolate `AppEntity`/`AppEnum` parameters, not raw strings.
struct SearchTermEntity: AppEntity, Identifiable {
    var id: String
    var term: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Search Term"
    static var defaultQuery = SearchTermEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(term)")
    }

    init(term: String) {
        self.id = term
        self.term = term
    }
}

struct SearchTermEntityQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SearchTermEntity] {
        identifiers.map { SearchTermEntity(term: $0) }
    }

    func entities(matching string: String) async throws -> [SearchTermEntity] {
        Logger(subsystem: "nl.ltvb.music", category: "SiriEntity")
            .log("SearchTermEntityQuery.entities(matching:) string=\(string, privacy: .public)")
        return [SearchTermEntity(term: string)]
    }

    func suggestedEntities() async throws -> [SearchTermEntity] {
        []
    }
}
