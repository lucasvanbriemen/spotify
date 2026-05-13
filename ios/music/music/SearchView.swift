import SwiftUI

struct SearchView: View {
    @State var searchText: String = ""
    @State var songs: [Song] = []
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    ForEach(songs) { song in
                        SongListingView(song: song, bgColor: Color.clear, playlistID: 1)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search songs")
        .onChange(of: searchText) { oldValue, newValue in
            Task {
                await getSongs()
            }
        }
    }
    
    func getSongs() async {
        songs = await SeverApi.get(endpoint: "search?q=\(searchText)") ?? []
    }
}
