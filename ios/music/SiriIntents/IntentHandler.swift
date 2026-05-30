import Intents

/// Thin SiriKit media extension. Its only job is to make Siri *discover* this app
/// as a media provider for "Play X" requests (via IntentsSupported in Info.plist)
/// and then hand the request to the main app, which owns the search + playback code.
class IntentHandler: INExtension, INPlayMediaIntentHandling {
    override func handler(for intent: INIntent) -> Any {
        return self
    }

    func handle(intent: INPlayMediaIntent,
                completion: @escaping (INPlayMediaIntentResponse) -> Void) {
        // Defer to the app process; PlayMediaIntentHandler in the app does the real work.
        completion(INPlayMediaIntentResponse(code: .handleInApp, userActivity: nil))
    }
}
