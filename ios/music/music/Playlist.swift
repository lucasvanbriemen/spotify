import Foundation

class Playlist: Codable, Identifiable {
    var id: Int
    var name: String
    var image: String?
}
