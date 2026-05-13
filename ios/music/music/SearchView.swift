import SwiftUI

struct SearchView: View {
    @State var searchText: String = ""
    @State var songs: [Song] = []
    
    var body: some View {
        NavigationStack {
            VStack {
                Text("Search")
                
                ForEach(songs) { song in
                    SongListingView(song: song, bgColor: Color.clear, playlistID: 1)
                }
            }
        }
        .searchable(text: $searchText)
    }
    
    func getSongs() async {
        songs = await SeverApi.get(endpoint: "songs?q=\(searchText)") ?? []
    }
}
