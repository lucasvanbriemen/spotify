#if os(iOS)
import Intents
import UIKit

/// SiriKit media-domain support: this is what lets a bare "Hey Siri, play
/// Thriller" (no app name) reach the app. Siri shows a "Which app?" picker the
/// first few times and learns the preference; with an app name, "Play Thriller
/// on LTVB" works immediately. Complements — not replaces — the App Shortcuts
/// phrases in MusicShortcuts, which remain the "… in Music" path.
///
/// SiriKit passes the raw spoken search string, so unlike App Shortcuts there
/// is no donated-vocabulary limit: resolution reuses the same PlaylistLibrary
/// matching the App Intent uses.
final class PlayMediaIntentHandler: NSObject, INPlayMediaIntentHandling {

    /// Sentinel INMediaItem identifier for requests with no search terms
    /// ("Hey Siri, play my music on LTVB") — resolved to a library shuffle.
    static let shuffleIdentifier = "shuffle:library"

    func resolveMediaItems(for intent: INPlayMediaIntent) async -> [INPlayMediaMediaItemResolutionResult] {
        let spoken = [intent.mediaSearch?.mediaName, intent.mediaSearch?.artistName]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        guard !spoken.isEmpty else {
            let mix = INMediaItem(
                identifier: Self.shuffleIdentifier,
                title: "My Playlists",
                type: .playlist,
                artwork: nil
            )
            return [.success(with: mix)]
        }

        let matches = await PlaylistLibrary.shared.songs(matching: spoken)
        guard !matches.isEmpty else {
            return [INPlayMediaMediaItemResolutionResult.unsupported()]
        }

        // Best match first; Siri can offer the runners-up as alternatives.
        let items = matches.prefix(3).map { song in
            INMediaItem(
                identifier: song.isrc,
                title: SongEntity.sayableTitle(song.title),
                type: .song,
                artwork: nil,
                artist: song.artist
            )
        }
        return INPlayMediaMediaItemResolutionResult.successes(with: Array(items))
    }

    func handle(intent: INPlayMediaIntent) async -> INPlayMediaIntentResponse {
        // .handleInApp is Apple's demonstrated response for background audio:
        // playback starts with no UI opening (WWDC20 10061).
        let started = await Self.startPlayback(for: intent)
        return INPlayMediaIntentResponse(code: started ? .handleInApp : .failure, userActivity: nil)
    }

    /// Starts playback for a resolved intent. Idempotent, because the system
    /// can deliver the intent both through the in-app handler and through the
    /// legacy application(_:handle:completionHandler:) launch path.
    @MainActor
    static func startPlayback(for intent: INPlayMediaIntent) async -> Bool {
        guard let identifier = intent.mediaItems?.first?.identifier else { return false }

        if identifier == shuffleIdentifier {
            guard let song = await PlaylistLibrary.shared.songs().randomElement() else { return false }
            PlayerManager.shared.playSong(song: song)
            return true
        }

        if PlayerManager.shared.currentlyPlaying?.isrc == identifier, PlayerManager.shared.isPlaying {
            return true // Already playing this exact song — don't restart it.
        }

        guard let song = await PlaylistLibrary.shared.song(withISRC: identifier) else { return false }
        PlayerManager.shared.playSong(song: song)
        return true
    }
}

/// Hosts the SiriKit entry points. Siri only consults this in apps that
/// support multiple scenes (the generated scene manifest already does).
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// In-app intent handling (iOS 14+): the whole resolve/handle pipeline
    /// runs in this process, launched in the background if needed.
    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        intent is INPlayMediaIntent ? PlayMediaIntentHandler() : nil
    }

    /// Fallback for the .handleInApp background-launch path, in case the
    /// system delivers the final playback request here instead.
    func application(_ application: UIApplication, handle intent: INIntent, completionHandler: @escaping (INIntentResponse) -> Void) {
        guard let playMedia = intent as? INPlayMediaIntent else {
            completionHandler(INPlayMediaIntentResponse(code: .failure, userActivity: nil))
            return
        }
        Task { @MainActor in
            let started = await PlayMediaIntentHandler.startPlayback(for: playMedia)
            completionHandler(INPlayMediaIntentResponse(code: started ? .success : .failure, userActivity: nil))
        }
    }
}

enum SiriMediaContext {
    /// Publishing an INMediaUserContext "increases the likelihood of the
    /// system sending intents that don't include an app name to this app"
    /// (Apple) — it's the documented lever for winning bare "play X" requests.
    static func publish(librarySize: Int) {
        let context = INMediaUserContext()
        context.numberOfLibraryItems = librarySize
        context.subscriptionStatus = .subscribed // Personal server: full access.
        context.becomeCurrent()
    }
}
#endif
