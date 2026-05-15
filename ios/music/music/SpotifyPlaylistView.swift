import SwiftUI

struct SpotifyPlaylistView: View {
    let playlistID: String
    @State var playlist: SpotifyPlaylist?
    @State var isLoading: Bool = true
    @State private var manager = PlayerManager.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                if !isLoading, let playlist {
                    ZStack(alignment: .bottomLeading) {
                        ZStack {
                            AsyncImage(url: URL(string: playlist.imageUrl ?? "")) { image in
                                image.resizable().blur(radius: 1)
                            } placeholder: {
                                ProgressView()
                            }

                            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                        }
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 32))

                        HStack {
                            Button(action: { manager.playPlaylist(playlist: playlist) }) {
                                Image(systemName: manager.isCurrentlyPlayingPlaylist(playlistId: "deezer:\(playlistID)") ? "pause" : "play")
                                    .font(Font.system(size: 32))
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                            .background(Color.accentColor)
                            .foregroundStyle(Color.white)
                            .clipShape(Circle())

                            VStack(alignment: .leading) {
                                Text(playlist.name)
                                    .font(Font.largeTitle.bold())
                                Text("\(playlist.songs?.count ?? 0) songs, \(playlistDuration())")
                            }
                            .foregroundStyle(Color.white)
                            .padding(.leading, 8)
                        }
                        .padding(16)
                    }

                    ForEach(Array((playlist.songs ?? []).enumerated()), id: \.element.id) { index, song in
                        let bg: Color = index.isMultiple(of: 2) ? .clear : Color(.secondarySystemBackground)
                        SongListingView(song: song, bgColor: bg, spotifyPlaylist: playlist, songIndex: index)
                    }
                }
            }
            .padding([.leading, .trailing], 10)
        }
        .task {
            await getPlaylist()
        }
    }

    func getPlaylist() async {
        playlist = await SeverApi.get(endpoint: "deezer-playlist/\(playlistID)")
        isLoading = false
    }

    func playlistDuration() -> String {
        guard let songs = playlist?.songs else {
            return "0 min"
        }

        let totalSeconds = songs.reduce(0) { $0 + $1.duration }
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        return "\(hours) hr \(minutes) min"
    }
}
