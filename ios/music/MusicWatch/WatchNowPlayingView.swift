import SwiftUI

struct WatchNowPlayingView: View {
    @State private var player = WatchPlayerManager.shared

    var body: some View {
        VStack(spacing: 8) {
            if let song = player.currentlyPlaying {
                AsyncImage(url: URL(string: song.imageUrl ?? "")) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "music.note")
                                .foregroundStyle(.secondary)
                        }
                }
                .frame(width: 70, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(spacing: 1) {
                    Text(song.title)
                        .font(.footnote.bold())
                        .lineLimit(1)
                    Text(song.artist ?? "Unknown Artist")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 12) {
                    Button {
                        player.playPreviousSong()
                    } label: {
                        Image(systemName: "backward.fill")
                    }
                    .buttonStyle(.plain)

                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .resizable()
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain)

                    Button {
                        player.playNextSong()
                    } label: {
                        Image(systemName: "forward.fill")
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Nothing playing")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Now Playing")
    }
}
