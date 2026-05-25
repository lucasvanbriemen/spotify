import SwiftUI

struct NavigationView: View {
    
    @State var playlists: [Playlist] = []
    
    var body: some View {
        #if os(iOS)
        TabView {
            Tab("Playlists", systemImage: "play.square.stack", content: { PlaylistOverviewView() })
            Tab(role: .search, content: { SearchView() })
        }
        .tabViewBottomAccessory(isEnabled: PlayerManager.shared.currentlyPlaying != nil, content: { PlayerView() })
        .tabBarMinimizeBehavior(TabBarMinimizeBehavior.onScrollDown)
        #else
        NavigationSplitView() {
            List() {
                Section(header: Text("Playlists")) {
                    ForEach(playlists) { playlist in
                        NavigationLink(destination: PlaylistView(playlistID: playlist.id)) {
                            ZStack(alignment: .bottomLeading) {
                                PlaylistBackgroundView(playlist: playlist, height: 50)
                                Text(playlist.name)
                                    .foregroundStyle(Color.white)
                                    .font(Font.largeTitle.bold())
                                    .padding(16)
                                
                            }
                        }
                    }
                }
                
                Section(header: Text("Search")) {
                    NavigationLink {
                        SearchView()
                    } label: {
                        Text("Search")
                    }
                }

            }
        } detail: {
            ContentUnavailableView {
                Label("Open playlist to play music", systemImage: "music.note.slash")
            } description: {
                Text("Open a playlist in the sidebar to start playing some fire music!!")
            }
        }
        .task {
            await getPlaylists()
        }
        #endif
    }
    
    func getPlaylists() async {
        playlists = await ServerApi.get(endpoint: "playlists") ?? []
    }
}
