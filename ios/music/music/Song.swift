import Foundation

class Song: Codable, Identifiable {
    var id: Int
    var name: String
    var durationMS: Int
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case durationMS = "duration_ms"
    }
}
