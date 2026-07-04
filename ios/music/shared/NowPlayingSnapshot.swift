import Foundation

/// Now-playing state shared with the home-screen widget through the app group
/// container. The app writes it on every song or play-state change; the widget's
/// timeline provider reads it. Artwork travels as a JPEG file next to it because
/// UserDefaults is too small for image blobs.
struct NowPlayingSnapshot: Codable {
    static let appGroupId = "group.nl.ltvb.music"
    static let defaultsKey = "nowPlayingSnapshot"
    static let artworkFilename = "widget-artwork.jpg"
    static let widgetKind = "NowPlayingWidget"

    var title: String
    var artist: String?
    var isPlaying: Bool

    static func load() -> NowPlayingSnapshot? {
        guard
            let data = UserDefaults(suiteName: appGroupId)?.data(forKey: defaultsKey),
            let snapshot = try? JSONDecoder().decode(NowPlayingSnapshot.self, from: data)
        else { return nil }
        return snapshot
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroupId)?.set(data, forKey: Self.defaultsKey)
    }

    static func clear() {
        UserDefaults(suiteName: appGroupId)?.removeObject(forKey: defaultsKey)
        saveArtwork(nil)
    }

    private static var artworkURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent(artworkFilename)
    }

    static func loadArtwork() -> Data? {
        guard let url = artworkURL else { return nil }
        return try? Data(contentsOf: url)
    }

    static func saveArtwork(_ data: Data?) {
        guard let url = artworkURL else { return }
        if let data {
            try? data.write(to: url)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
