import SwiftUI

struct ContentView: View {
    @State var playlists: [Playlist] = []
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading) {
                    Text("Playlists")
                        .fontWeight(.bold)
                        .padding([.top, .leading], 16)
                        .foregroundStyle(Color(.label))

                    ForEach(playlists) { playlist in
                        NavigationLink(destination: PlaylistView(playlistID: playlist.id)) {
                            ZStack(alignment: .bottomLeading) {
                                PlaylistBackgroundView(playlist: playlist)

                                Text(playlist.name)
                                    .foregroundStyle(Color.white)
                                    .font(Font.largeTitle.bold())
                                    .padding(16)
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
        
        .task {
            await getPlaylists()
        }
    }
    
    func getPlaylists() async {
        playlists = await SeverApi.get(endpoint: "playlists") ?? []
    }
}

#Preview {
    ContentView()
}
