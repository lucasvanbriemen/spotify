import SwiftUI

struct SearchView: View {
    @State var searchText: String = ""
    @State var songs: [Song] = []
    @State var playlists: [Playlist] = []
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    ForEach(songs.enumerated(), id: \.element.id) { index, song in
                        let bg: Color = index.isMultiple(of: 2) ? .clear : Color(.secondarySystemBackground)
                        SongListingView(song: song, bgColor: bg)
                    }
                    
                    NavigationStack {
                        Text("Playlists")
                            .font(.headline)
                            .padding(.top, 16)
                        
                        ForEach(playlists.enumerated(), id: \.element.id) { index, playlist in
                            let bg: Color = index.isMultiple(of: 2) ? .clear : Color(.secondarySystemBackground)

                            NavigationLink(destination: PlaylistView(playlistID: playlist.id)) {
                                PlaylistListingView(playlist: playlist, bgColor: bg)
                            }
                        }
                    }
                    
                }
                .padding([.trailing, .leading], 8)
            }
        }
        .searchable(text: $searchText, prompt: "Search songs")
        .onChange(of: searchText) { oldValue, newValue in
            Task {
                await getResults()
            }
        }
    }
    
    func getResults() async {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        
        if searchText.count < 3 {
            return
        }
        
        let query = searchText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let serverResults: SearchResults? = await SeverApi.get(endpoint: "search?q=\(query)")
        songs = serverResults?.songs ?? []
        playlists = serverResults?.playlists ?? []
    }
}
