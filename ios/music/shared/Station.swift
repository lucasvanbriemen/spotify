import Foundation

/// A radio station curated by the server (genre, decade, or smart mix). The
/// client never sees the full programme — it just asks the station for the
/// next chunk of queue items.
struct Station: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var image: String?
    var language: String?

    enum CodingKeys: String, CodingKey {
        case id, name, language
        case image = "image_url"
    }
}

struct StationsResponse: Codable {
    var stations: [Station]
}

struct StationQueueResponse: Codable {
    var items: [Song]
    var startOffset: Int?

    enum CodingKeys: String, CodingKey {
        case items
        case startOffset = "start_offset"
    }
}
