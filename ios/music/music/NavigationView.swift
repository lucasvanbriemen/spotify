import SwiftUI

struct NavigationView: View {
    var body: some View {
        TabView {
            Tab("Playlists", systemImage: "play.square.stack", content: { PlaylistOverviewView() })
            Tab("Search", systemImage: "magnifyingglass", content: { PlaylistOverviewView() })
        }
    }
}
