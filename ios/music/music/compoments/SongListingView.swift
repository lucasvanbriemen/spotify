import SwiftUI

struct SongListingView: View {
    let manager = PlayerManager.shared
    let song: Song
    let bgColor: Color
    var shouldPlaySong: Bool? = true
    var playlist: Playlist? = nil
    var songIndex: Int? = nil
    
    var body: some View {
        Button() {
            if shouldPlaySong == false {
                return
            }

            if playlist == nil {
                manager.playSong(song: song)
            } else {
                manager.playPlaylist(playlist: playlist!, atIndex: songIndex!)
                manager.playingPlaylistId = playlist?.id
            }
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
                
                Spacer()
                
                SongMenuView(song: song)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(Color.primary)
        }
    }
}
