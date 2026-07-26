import SwiftUI

/// Blurred artwork banner with a darkening gradient, used as the backdrop for
/// playlist and radio station cards/headers.
struct PlaylistBackgroundView: View {
    let imageUrl: String?
    var height: CGFloat? = 200

    init(imageUrl: String?, height: CGFloat? = 200) {
        self.imageUrl = imageUrl
        self.height = height
    }

    init(playlist: Playlist, height: CGFloat? = 200) {
        self.init(imageUrl: playlist.image, height: height)
    }

    var body: some View {
        ZStack {
            AsyncImage(url: URL(string: imageUrl ?? "")) { image in
                image.resizable().blur(radius: 1)
            } placeholder: {
                ProgressView()
            }

            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)

        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 32))
    }
}
