import SwiftUI
import Foundation

struct PlaylistView: View {
    let playlistID: String
    @State var playlist: Playlist?
    @State var isLoading: Bool = true
    @State var isLoopingUneven: Bool = false
    @State private var manager = PlayerManager.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                if !isLoading, let playlist {
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
                    
                    ForEach(Array((playlist.songs ?? []).enumerated()), id: \.element.id) { index, song in
                        let bg: Color = index.isMultiple(of: 2) ? .clear : Color.secondaryListBackground
                        SongListingView(song: song, bgColor: bg, playlist: playlist, songIndex: index)
                    }
                }
            }
            .padding([.leading, .trailing], 10)
        }
        .task(id: playlistID) {
            isLoading = true
            playlist = nil
            await getPlaylist()
        }
    }


    func getPlaylist() async {
        playlist = await SeverApi.get(endpoint: "playlist/\(String(playlistID))")
        isLoading = false
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
