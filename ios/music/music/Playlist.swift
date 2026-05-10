import Foundation

class Playlist: Codable, Identifiable {
    var id: Int
    var name: String
    var image: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case image = "image_url"
    }
}
