import Foundation

class Song: Codable, Identifiable {
    var id: Int
    var title: String
    var duration: Int
    var fileId: String?
    var imageUrl: String?
    var artist: String?
    
    enum CodingKeys: String, CodingKey {
        case id, title, artist, duration
        case fileId = "file_id"
        case imageUrl = "image_url"
    }
}
