import SwiftUI

struct SearchView: View {
    @State var searchText: String = ""
    @State var songs: [Song] = []
    @State var playlists: [SpotifyPlaylist] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading) {
                    if !playlists.isEmpty {
                        Text("Playlists")
                            .fontWeight(.bold)
                            .padding([.top, .leading], 8)

                        ForEach(playlists) { playlist in
                            NavigationLink(destination: SpotifyPlaylistView(playlistID: playlist.id)) {
                                SpotifyPlaylistResultView(playlist: playlist)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !songs.isEmpty {
                        Text("Songs")
                            .fontWeight(.bold)
                            .padding([.top, .leading], 8)

                        ForEach(songs.enumerated(), id: \.element.id) { index, song in
                            let bg: Color = index.isMultiple(of: 2) ? .clear : Color(.secondarySystemBackground)
                            SongListingView(song: song, bgColor: bg)
                        }
                    }
                }
                .padding([.trailing, .leading], 8)
            }
        }
        .searchable(text: $searchText, prompt: "Search songs and playlists")
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

        let results: SearchResults? = await SeverApi.get(endpoint: "search?q=\(searchText)&types=track,playlist")
        songs = results?.tracks ?? []
        playlists = results?.playlists ?? []
    }
}

struct SpotifyPlaylistResultView: View {
    let playlist: SpotifyPlaylist

    var body: some View {
        HStack(alignment: .center) {
            AsyncImage(url: URL(string: playlist.imageUrl ?? "")) { image in
                image.resizable()
            } placeholder: {
                ProgressView()
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading) {
                Text(playlist.name)
                    .fontWeight(.bold)
                    .frame(height: 18)
                    .truncationMode(.tail)
                Text("\(playlist.trackCount ?? 0) songs · \(playlist.owner ?? "")")
                    .font(Font.system(size: 14, weight: .light))
                    .frame(height: 18)
                    .truncationMode(.tail)
            }

            Spacer()
        }
        .padding(8)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(Color.primary)
    }
}
