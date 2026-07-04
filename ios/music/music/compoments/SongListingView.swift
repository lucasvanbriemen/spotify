import SwiftUI

struct SongListingView: View {
    let manager = PlayerManager.shared
    let song: Song
    let bgColor: Color
    var shouldPlaySong: Bool? = true
    var playlist: Playlist? = nil
    var songIndex: Int? = nil

    // macOS rows are denser than the touch-sized iOS ones: smaller artwork,
    // system list typography, and no fixed label heights.
    #if os(macOS)
    private let artworkSize: CGFloat = 36
    private let rowPadding: CGFloat = 6
    private let cornerRadius: CGFloat = 6
    #else
    private let artworkSize: CGFloat = 48
    private let rowPadding: CGFloat = 8
    private let cornerRadius: CGFloat = 8
    #endif

    private var isCurrentSong: Bool {
        manager.currentlyPlaying?.isrc == song.isrc
    }

    var body: some View {
        Button() {
            if shouldPlaySong == false {
                return
            }

            if playlist == nil {
                manager.playSong(song: song)
            } else {
                manager.playPlaylist(playlist: playlist!, atIndex: songIndex!)
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                AsyncImage(url: URL(string: song.imageUrl!)) { image in
                    image.resizable()
                } placeholder: {
                    ProgressView()
                }
                .frame(width: artworkSize, height: artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

                #if os(macOS)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isCurrentSong ? Color.accentColor : Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(song.artist!)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                #else
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
                #endif

                Spacer()

                #if os(macOS)
                if isCurrentSong {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                }
                #endif

                SongMenuView(song: song)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(rowPadding)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .foregroundStyle(Color.primary)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
    }
}
