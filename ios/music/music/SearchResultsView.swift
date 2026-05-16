import SwiftUI

struct SearchResultsView: View {
    let query: String
    @State private var songs: [Song] = []
    @State private var playlists: [Playlist] = []

    var body: some View {
        ScrollView {
            VStack {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    let bg: Color = index.isMultiple(of: 2) ? .clear : Color.secondaryListBackground
                    SongListingView(song: song, bgColor: bg)
                }

                if !playlists.isEmpty {
                    Text("Playlists")
                        .font(.headline)
                        .padding(.top, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(Array(playlists.enumerated()), id: \.element.id) { index, playlist in
                        let bg: Color = index.isMultiple(of: 2) ? .clear : Color.secondaryListBackground

                        NavigationLink(destination: PlaylistView(playlistID: playlist.id)) {
                            PlaylistListingView(playlist: playlist, bgColor: bg)
                        }
                    }
                }
            }
            .padding([.trailing, .leading], 8)
            .frame(maxWidth: 880)
            .frame(maxWidth: .infinity)
        }
        .task(id: query) {
            await getResults()
        }
    }

    func getResults() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.count < 3 {
            songs = []
            playlists = []
            return
        }

        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let serverResults: SearchResults? = await SeverApi.get(endpoint: "search?q=\(encoded)")
        songs = serverResults?.songs ?? []
        playlists = serverResults?.playlists ?? []
    }
}
