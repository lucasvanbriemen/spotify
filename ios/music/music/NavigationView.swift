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
                            Text(playlist.name)
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
            Text("Details")
        }
        .task {
            await getPlaylists()
        }
        #endif
    }
    
    func getPlaylists() async {
        playlists = await SeverApi.get(endpoint: "playlists") ?? []
    }
}
