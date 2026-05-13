import SwiftUI

struct SongListingView {
    let manager = PlayerManager.shared
    let song: Song
    let bgColor: Color
    let playlistID: Int
    
    var body: some View {
        Button {
            manager.playSong(song: song)
            manager.playingPlaylistId = playlistID
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
        }
        .foregroundStyle(Color.primary)
    }
}
