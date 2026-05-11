import SwiftUI
import Foundation

struct PlaylistView: View {
    @State var playlistID: Int
    @State var playlist: Playlist?
    @State var isLoading: Bool = true
    
    init(playlistID: Int) {
        self.playlistID = playlistID
    }
    
    var body: some View {
        ScrollView {
            LazyVStack {
                if !isLoading, let playlist {
                    ZStack(alignment: .bottomLeading) {
                        ZStack {
                            AsyncImage(url: URL(string: playlist.image!)) { image in
                                image.resizable()
                                    .blur(radius: 1)
                            } placeholder: {
                                ProgressView()
                            }

                            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                                
                        }
                            .frame(width: 400, height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 32))

                        VStack(alignment: .leading) {
                            Text(playlist.name)
                                .font(Font.largeTitle.bold())
                            Text(String(playlist.songs?.count ?? 0) + " songs, \(playlistDuration())")
                        }
                        .foregroundStyle(Color.white)
                        .padding(16)
                    }
                    
                    ForEach(playlist.songs ?? []) { song in
                        Button() {
                            PlayerData.shared.currentlyPlaying = song
                        } label: {
                            HStack(alignment: .top) {
                                AsyncImage(url: URL(string: song.imageUrl!)) { image in
                                    image.resizable()
                                } placeholder: {
                                    ProgressView()
                                }
                                .frame(width: 32, height: 32)

                                VStack(alignment: .leading) {
                                    Text(song.name)
                                    Text(song.artist!)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            await getPlaylist()
        }
    }
    
    
    func getPlaylist() async {
        do {
            playlist = try await SeverApi.get(endpoint: "playlist/\(String(playlistID))")
            isLoading = false
            print(playlist?.songs?.count ?? 0)
        } catch {
            print(error)
        }
    }
    
    func playlistDuration() -> String {
        if playlist?.songs == nil {
            return "0 min"
        }
        
        var totalMS: Int = 0
        
        for song in playlist!.songs! {
            totalMS += song.durationMS
        }
        
        let totalSeconds = totalMS / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        return "\(hours) hr \(minutes) min"
    }
}
