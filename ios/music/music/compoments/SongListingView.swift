import SwiftUI

struct SongListingView: View {
    let manager = PlayerManager.shared
    let song: Song
    let bgColor: Color
    var playlistID: Int? = nil
    
    var body: some View {
        Menu() {
            Button("Duplicate", action: { print("Duplicate") })
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
                    Text(song.title)
                        .fontWeight(Font.Weight.bold)
                        .frame(height: 18)
                        .truncationMode(.tail)
                    Text(song.artist!)
                        .font(Font.system(size: 14, weight: .light, design: .default))
                        .frame(height: 18)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(Color.primary)
        } primaryAction: {
            manager.playSong(song: song)
            
            if playlistID != nil {
                manager.playingPlaylistId = playlistID
            }
        }
    }
}
