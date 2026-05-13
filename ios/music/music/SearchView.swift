import SwiftUI

struct SearchView: View {
    @State var searchText: String = ""
    @State var songs: [Song] = []
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    ForEach(songs.enumerated(), id: \.element.id) { index, song in
                        let bg: Color = index.isMultiple(of: 2) ? .clear : Color(.secondarySystemBackground)
                        SongListingView(song: song, bgColor: bg)
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
