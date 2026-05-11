import SwiftUI
import Foundation

struct PlaylistView: View {
    @State var playlistID: Int
    @State var playlist: Playlist?
    @State var isLoading: Bool = true
    @State var isLoopingUneven: Bool = false
    
    init(playlistID: Int) {
        self.playlistID = playlistID
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
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
                        
                        HStack() {
                            Button(action: { print("play playlist") }) {
                                Image(systemName: "play")
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                            .background(Color.accentColor)
                            .foregroundStyle(Color.white)
                            .clipShape(Circle())
                            
                            VStack(alignment: .leading) {
                                Text(playlist.name)
                                    .font(Font.largeTitle.bold())
                                Text(String(playlist.songs?.count ?? 0) + " songs, \(playlistDuration())")
                            }
                            .foregroundStyle(Color.white)
                            .padding(.leading, 8)
                            
                        }
                        .padding(16)
                    }
                    
                    ForEach(Array((playlist.songs ?? []).enumerated()), id: \.element.id) { index, song in
                        Button {
                            PlayerData.shared.currentlyPlaying = song
                        } label: {
                            HStack(alignment: .center) {
                                AsyncImage(url: URL(string: song.imageUrl!)) { image in
                                    image.resizable()
                                } placeholder: {
                                    ProgressView()
                                }
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading) {
                                    Text(song.name)
                                        .fontWeight(Font.Weight.bold)
                                        .frame(width: .infinity, height: 18)
                                        .truncationMode(.tail)
                                    Text(song.artist!)
                                        .font(Font.system(size: 14, weight: .light, design: .default))
                                        .frame(width: .infinity, height: 18)
                                        .truncationMode(.tail)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(index.isMultiple(of: 2) ? Color(.clear) : Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .foregroundStyle(Color.primary)
                        .frame(width: 400)
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
