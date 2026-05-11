import Foundation

class Song: Codable, Identifiable {
    var id: Int
    var name: String
    var durationMS: Int
    var mp3Url: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case durationMS = "duration_ms"
        case mp3Url = "mp3_url"
    }
}
