import Foundation

class Playlist: Codable, Identifiable {
    var id: String
    var name: String
    var image: String?
    var author: String?
    var trackCount: Int?
    var songs: [Song]?
    
    enum CodingKeys: String, CodingKey {
        case id, name, songs, author
        case image = "image_url"
        case trackCount = "track_count"
    }
}
