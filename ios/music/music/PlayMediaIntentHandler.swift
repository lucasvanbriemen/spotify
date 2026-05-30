#if os(iOS)
import UIKit
import Intents
import AppIntents

/// App delegate that opts the app into SiriKit's media domain so phrases like
/// "Play money for nothing" (no app name) can be routed here by Siri.
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        INPreferences.requestSiriAuthorization { _ in }
        // Tell Siri the current playlist names so they can be matched inside
        // App Shortcut phrases like "Listen to Car in My Library".
        MusicShortcuts.updateAppShortcutParameters()
        return true
    }

    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        if intent is INPlayMediaIntent {
            return PlayMediaIntentHandler()
        }
        return nil
    }
}

/// Resolves the spoken media request to a song and starts playback.
final class PlayMediaIntentHandler: NSObject, INPlayMediaIntentHandling {
    func resolveMediaItems(for intent: INPlayMediaIntent,
                           with completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void) {
        guard let name = searchTerm(from: intent), !name.isEmpty else {
            completion([.unsupported()])
            return
        }

        Task {
            guard let song = await topMatch(for: name) else {
                completion([INPlayMediaMediaItemResolutionResult.unsupported()])
                return
            }
            let item = INMediaItem(identifier: song.isrc, title: song.title, type: .song,
                                   artwork: nil, artist: song.artist)
            completion([INPlayMediaMediaItemResolutionResult.success(with: item)])
        }
    }

    func handle(intent: INPlayMediaIntent,
                completion: @escaping (INPlayMediaIntentResponse) -> Void) {
        guard let name = searchTerm(from: intent), !name.isEmpty else {
            completion(INPlayMediaIntentResponse(code: .failure, userActivity: nil))
            return
        }

        Task {
            guard let song = await topMatch(for: name) else {
                completion(INPlayMediaIntentResponse(code: .failure, userActivity: nil))
                return
            }
            PlayerManager.shared.playSong(song: song)
            completion(INPlayMediaIntentResponse(code: .success, userActivity: nil))
        }
    }

    // MARK: - Helpers

    private func searchTerm(from intent: INPlayMediaIntent) -> String? {
        intent.mediaSearch?.mediaName ?? intent.mediaItems?.first?.title
    }

    private func topMatch(for name: String) async -> Song? {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let results: SearchResults? = await ServerApi.get(endpoint: "search?q=\(encoded)")
        return results?.songs.first
    }
}
#endif
