import SwiftUI

struct NavigationView: View {
    @State private var manager = PlayerManager.shared

    #if os(macOS)
    @State private var playlists: [Playlist] = []
    @State private var selectedPlaylistID: String?
    @State private var searchText: String = ""
    #endif

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            NavigationSplitView {
                List(selection: $selectedPlaylistID) {
                    Section("Playlists") {
                        ForEach(playlists) { playlist in
                            Label(playlist.name, systemImage: "music.note.list")
                                .lineLimit(1)
                                .tag(playlist.id as String?)
                        }
                    }
                }
                .searchable(text: $searchText, placement: .sidebar, prompt: "Search songs")
                .navigationSplitViewColumnWidth(min: 200, ideal: 260)
                .task { await loadPlaylists() }
            } detail: {
                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    NavigationStack {
                        SearchResultsView(query: searchText)
                    }
                } else if let id = selectedPlaylistID {
                    NavigationStack {
                        PlaylistView(playlistID: id)
                            .id(id)
                    }
                } else {
                    ContentUnavailableView(
                        "Choose a playlist",
                        systemImage: "music.note.list",
                        description: Text("Pick a playlist from the sidebar, or type to search.")
                    )
                }
            }

            if manager.currentlyPlaying != nil {
                Divider()
                PlayerView()
                    .background(.regularMaterial)
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 720, minHeight: 480)
        #else
        TabView {
            Tab("Playlists", systemImage: "play.square.stack", content: { PlaylistOverviewView() })
            Tab(role: .search, content: { SearchView() })
        }
        .tabViewBottomAccessory(isEnabled: manager.currentlyPlaying != nil, content: { PlayerView() })
        .tabBarMinimizeBehavior(TabBarMinimizeBehavior.onScrollDown)
        #endif
    }

    #if os(macOS)
    func loadPlaylists() async {
        playlists = await SeverApi.get(endpoint: "playlists") ?? []
    }
    #endif
}
