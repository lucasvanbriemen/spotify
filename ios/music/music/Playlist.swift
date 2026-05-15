import Foundation

class Playlist: Codable, Identifiable {
    var id: String
    var name: String
    var image: String?
    var songs: [Song]?
    
    enum CodingKeys: String, CodingKey {
        case id, name, songs
        case image = "image_url"
    }
}
