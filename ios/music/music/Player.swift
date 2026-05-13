import SwiftUI
import AVFoundation
import MediaPlayer

struct PlayerView: View {
    @State private var manager = PlayerManager.shared
    @State private var showingSheet: Bool = false

    var body: some View {
        Button(action: {
            showingSheet.toggle()
        }) {
            HStack(alignment: .center) {
                if let song = manager.currentlyPlaying {
                    AsyncImage(url: URL(string: song.imageUrl!)) { image in
                        image.resizable()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 32))
                    
                    VStack(alignment: .leading) {
                        Text(song.name)
                            .font(Font.system(size: 16, weight: .medium, design: .default))
                            .frame(height: 16)
                            .truncationMode(.tail)
                        Text(song.artist!)
                            .font(Font.system(size: 14, weight: .light, design: .default))
                            .frame(height: 14)
                            .truncationMode(.tail)
                            .foregroundStyle(Color.secondary)
                    }
                    .foregroundStyle(Color.white)
                    
                    Spacer()
                    
                    Button(action: { manager.togglePlayPause() }) {
                        Image(systemName: manager.isPlaying ? "pause" : "play")
                            .font(.system(size: 24, weight: .bold, design: .default))
                            .foregroundStyle(Color.white)
                            .padding(16)
                    }
                }
            }
            .padding([.leading, .trailing], 8)
            .frame(width: 390, height: 64)
            .background(Color(red: 0.11, green: 0.73, blue: 0.33))
            .clipShape(Capsule())
        }
        .sheet(isPresented: $showingSheet) {
            Text(manager.currentlyPlaying?.name ?? "No song selected")
        }
    }
}
