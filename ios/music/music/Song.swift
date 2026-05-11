import Foundation

class Song: Codable, Identifiable {
    var id: Int
    var name: String
    var durationMS: Int
    var mp3Url: String?
    var imageUrl: String?
    var artist: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, artist
        case durationMS = "duration_ms"
        case mp3Url = "mp3_url"
        case imageUrl = "image_url"
    }
}
