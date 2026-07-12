import SwiftUI
import AppIntents

@main
struct musicApp: App {
    #if os(iOS)
    // Routes SiriKit media intents ("Hey Siri, play Thriller") to
    // PlayMediaIntentHandler — see AppDelegate there.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        // Refresh the set of songs Siri knows about so newly-added playlist
        // tracks become sayable ("Play <song> in Music").
        MusicShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            NavigationView()
        }
    }
}
