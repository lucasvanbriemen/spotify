import AppIntents

struct MusicShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayPlaylistIntent(),
            phrases: [
                "Listen to \(\.$playlist) in \(.applicationName)",
                "Listen to the \(\.$playlist) playlist in \(.applicationName)",
                "Put on \(\.$playlist) in \(.applicationName)",
                "Put on the \(\.$playlist) playlist in \(.applicationName)",
                "Start \(\.$playlist) in \(.applicationName)",
                "Start the \(\.$playlist) playlist in \(.applicationName)"
            ],
            shortTitle: "Listen to Playlist",
            systemImageName: "play.circle"
        )

        AppShortcut(
            intent: SearchMusicIntent(),
            phrases: [
                "Listen to a song in \(.applicationName)",
                "Listen to a song on \(.applicationName)",
                "Search \(.applicationName) for a song",
                "Search for a song in \(.applicationName)",
                "Find a song in \(.applicationName)"
            ],
            shortTitle: "Listen to a Song",
            systemImageName: "play.circle"
        )

        AppShortcut(
            intent: PlaySomethingIntent(),
            phrases: [
                "Surprise me in \(.applicationName)",
                "Shuffle \(.applicationName)",
                "Shuffle my music in \(.applicationName)"
            ],
            shortTitle: "Surprise Me",
            systemImageName: "shuffle"
        )
    }
}
