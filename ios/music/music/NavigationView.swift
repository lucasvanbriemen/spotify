import SwiftUI

struct NavigationView: View {    
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
                NavigationLink {
                    PlaylistOverviewView()
                } label: {
                    Text("Playlists")
                }
                
                NavigationLink {
                    SearchView()
                } label: {
                    Text("Search")
                }

            }
        } detail: {
            Text("Details")
        }
        #endif
    }
}
