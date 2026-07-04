import SwiftUI
import AVFoundation
import MediaPlayer

struct PlayerView: View {
    @State private var manager = PlayerManager.shared

    var body: some View {
        Button(action: {
            manager.hasSheetOpen.toggle()
        }) {
            HStack(alignment: .center) {
                if let song = manager.currentlyPlaying {
                    AsyncImage(url: URL(string: song.imageUrl!)) { image in
                        image.resizable()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 32))

                    #if os(macOS)
                    // Natural line stacking; the fixed-height frames the iOS
                    // accessory needs squeeze the two lines together on macOS.
                    VStack(alignment: .leading, spacing: 1) {
                        Text(song.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(song.artist!)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(Color.secondary)
                    }
                    .foregroundStyle(Color.primary)
                    #else
                    VStack(alignment: .leading) {
                        Text(song.title)
                            .font(Font.system(size: 14, weight: .medium, design: .default))
                            .frame(height: 5)
                            .truncationMode(.tail)
                        Text(song.artist!)
                            .font(Font.system(size: 10, weight: .medium, design: .default))
                            .frame(height: 7)
                            .truncationMode(.tail)
                            .foregroundStyle(Color.secondary)
                    }
                    .foregroundStyle(Color.primary)
                    #endif

                    Spacer()

                    Button(action: { manager.togglePlayPause() }) {
                        Image(systemName: manager.isPlaying ? "pause" : "play")
                            .font(.system(size: 24, weight: .bold, design: .default))
                            .foregroundStyle(Color.secondary)
                            .padding(16)
                    }
                    #if os(macOS)
                    // Without this the play control renders as a bezeled AppKit
                    // push button and breaks the glass pill look.
                    .buttonStyle(.plain)
                    #endif
                }
            }
            .padding(8)
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
    }
}
