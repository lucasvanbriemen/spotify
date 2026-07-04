import SwiftUI
import AppIntents

@main
struct musicApp: App {
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
