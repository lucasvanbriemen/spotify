import SwiftUI
import Foundation

struct PlaylistView: View {
    @State var playlistID: String
    @State var playlist: Playlist?
    @State var isLoading: Bool = true
    @State var isLoopingUneven: Bool = false
    @State private var manager = PlayerManager.shared
    
    init(playlistID: String) {
        self.playlistID = playlistID
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                if !isLoading, let playlist {
                    #if os(macOS)
                    // Album-page style header: clean artwork square next to the
                    // title, on the window background — no blurred banner.
                    HStack(alignment: .bottom, spacing: 20) {
                        AsyncImage(url: URL(string: playlist.image ?? "")) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                        }
                        .frame(width: 168, height: 168)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.25), radius: 14, y: 8)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(playlist.name)
                                .font(.system(size: 32, weight: .bold))
                                .lineLimit(2)
                                .truncationMode(.tail)
                            Text("\(playlist.songs?.count ?? 0) songs · \(playlistDuration())")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Button(action: { manager.playPlaylist(playlist: playlist) }) {
                                Label(
                                    manager.isCurrentlyPlayingPlaylist(playlistId: playlistID) ? "Pause" : "Play",
                                    systemImage: manager.isCurrentlyPlayingPlaylist(playlistId: playlistID) ? "pause.fill" : "play.fill"
                                )
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .padding(.top, 10)
                        }
                        .padding(.bottom, 4)

                        Spacer(minLength: 0)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                    #else
                    ZStack(alignment: .bottomLeading) {
                        PlaylistBackgroundView(playlist: playlist)

                        HStack() {
                            Button(action: { manager.playPlaylist(playlist: playlist) }) {
                                Image(systemName: manager.isCurrentlyPlayingPlaylist(playlistId: playlistID) ? "pause" : "play")
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
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                                Text(String(playlist.songs?.count ?? 0) + " songs, \(playlistDuration())")
                            }
                            .foregroundStyle(Color.white)
                            .padding(.leading, 8)

                        }
                        .padding(16)
                    }
                    #endif

                    #if os(macOS)
                        // A hint of primary reads as a subtle zebra stripe in both
                        // light and dark mode; controlBackgroundColor was pure
                        // white on a white window and looked heavy.
                        let secondaryColor = Color.primary.opacity(0.045)
                    #else
                        let secondaryColor = Color(.secondarySystemBackground)
                    #endif
                    
                    ForEach(Array((playlist.songs ?? []).enumerated()), id: \.element.id) { index, song in
                        let bg: Color = index.isMultiple(of: 2) ? .clear : secondaryColor
                        SongListingView(song: song, bgColor: bg, playlist: playlist, songIndex: index)
                    }
                }
            }
            .padding([.leading, .trailing], 10)
            #if os(macOS)
            .padding([.leading, .trailing], 10) // extra breathing room in a wide window
            #endif
        }
        #if os(macOS)
        .navigationTitle(playlist?.name ?? "Playlist")
        #endif
        .task {
            await getPlaylist()
        }
    }
    
    
    func getPlaylist() async {
        playlist = await ServerApi.get(endpoint: "playlist/\(String(playlistID))")
        isLoading = false

        // Opening a playlist is a strong signal its songs are about to be
        // played — have the server cache any that aren't downloaded yet.
        ServerApi.warm(endpoint: "playlist/\(String(playlistID))/prepare")
    }
    
    func playlistDuration() -> String {
        if playlist?.songs == nil {
            return "0 min"
        }
        
        var totalSeconds: Int = 0
        for song in playlist!.songs! {
            totalSeconds += song.duration
        }
        
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        return "\(hours) hr \(minutes) min"
    }
}
