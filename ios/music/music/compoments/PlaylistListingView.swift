import SwiftUI

struct PlaylistListingView: View {
    let song: Playlist
    let bgColor: Color
    
    var body: some View {
      
            HStack(alignment: .center) {
                AsyncImage(url: URL(string: song.image!)) { image in
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
                    Text(song.name)
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
    }
}
