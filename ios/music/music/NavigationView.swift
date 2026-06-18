import SwiftUI

struct NavigationView: View {

    @State var playlists: [Playlist] = []
    @State var selectedPlaylistId: String?

    var body: some View {
        #if os(iOS)
        TabView {
            Tab("Playlists", systemImage: "play.square.stack", content: { PlaylistOverviewView() })
            Tab("Stats", systemImage: "chart.bar", content: { StatsView() })
            Tab(role: .search, content: { SearchView() })
        }
        .tabViewBottomAccessory(isEnabled: PlayerManager.shared.currentlyPlaying != nil, content: { PlayerView() })
        .sheet(isPresented: PlayerManager.shared.hasSheetOpen, content: {PlayerSheetView() })
        .tabBarMinimizeBehavior(TabBarMinimizeBehavior.onScrollDown)
        #else
        NavigationSplitView() {
            List {
                Section(header: Text("Playlists")) {
                    ForEach(playlists) { playlist in
                        Button {
                            selectedPlaylistId = playlist.id
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                PlaylistBackgroundView(playlist: playlist, height: 100)
                                Text(playlist.name)
                                    .foregroundStyle(Color.white)
                                    .font(Font.largeTitle.bold())
                                    .padding(16)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 32)
                                    .strokeBorder(Color.accentColor, lineWidth: selectedPlaylistId == playlist.id ? 5 : 0)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowBackground(Color.clear)
                    }
                }

                Section(header: Text("Search")) {
                    NavigationLink {
                        SearchView()
                    } label: {
                        Text("Search")
                    }
                }

                Section(header: Text("Stats")) {
                    NavigationLink {
                        StatsView()
                    } label: {
                        Text("Stats")
                    }
                }

            }
        } detail: {
            if let selectedPlaylistId {
                PlaylistView(playlistID: selectedPlaylistId)
            } else {
                ContentUnavailableView {
                    Label("Open playlist to play music", systemImage: "music.note.slash")
                } description: {
                    Text("Open a playlist in the sidebar to start playing some fire music!!")
                }
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
