import SwiftUI

struct PlaylistBackgroundView: View {
    let playlist: Playlist
    
    var body: some View {
        ZStack {
            AsyncImage(url: URL(string: playlist.image!)) { image in
                image.resizable().blur(radius: 1)
            } placeholder: {
                ProgressView()
            }

            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)

        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 32))
    }
}
