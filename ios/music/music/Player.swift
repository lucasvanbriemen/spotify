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
                    
                    Spacer()
                    
                    Button(action: { manager.togglePlayPause() }) {
                        Image(systemName: manager.isPlaying ? "pause" : "play")
                            .font(.system(size: 24, weight: .bold, design: .default))
                            .foregroundStyle(Color.secondary)
                            .padding(16)
                    }
                }
            }
            .padding(8)
        }
        .sheet(isPresented: $manager.hasSheetOpen, content: {PlayerSheetView() })
    }
}
