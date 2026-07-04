import AppIntents

/// Registers the spoken phrases Siri recognises. App Shortcut phrases must contain
/// the app name (`\(.applicationName)`), so the reliable form is "… in Music".
/// A bare "Hey Siri, play X" with no app name is routed by iOS to the system
/// default music service (usually Apple Music / Spotify) and cannot be claimed here.
struct MusicShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlaySongIntent(),
            phrases: [
                "Play \(\.$song) in \(.applicationName)",
                "Play \(\.$song) on \(.applicationName)",
                "Listen to \(\.$song) in \(.applicationName)",
                "Listen to \(\.$song) on \(.applicationName)",
                "Put on \(\.$song) in \(.applicationName)"
            ],
            shortTitle: "Play a Song",
            systemImageName: "music.note"
        )
    }
}
