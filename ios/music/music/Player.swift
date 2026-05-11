import SwiftUI
import AVFoundation

struct PlayerView: View {
    @State private var player: AVPlayer?
    private let playerData = PlayerData.shared

    var body: some View {
        HStack(alignment: .center) {
            if let song = playerData.currentlyPlaying {
                AsyncImage(url: URL(string: song.imageUrl!)) { image in
                    image.resizable()
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading) {
                    Text(song.name)
                        .fontWeight(Font.Weight.bold)
                    Text(song.artist!)
                        .font(Font.system(size: 14, weight: .light, design: .default))
                }
                
                Spacer()
                
                Button(action: togglePlay) {
                    Image(systemName: playerData.isPlaying ? "pause.circle" : "play.circle")
                        .font(.system(size: 24, weight: .bold, design: .default))
                }
            } else {
                EmptyView()
            }
        }
        .onChange(of: playerData.currentlyPlaying?.id) {
            play()
        }
    }

    private func play() {
        self.player?.pause()
        playerData.isPlaying = false
        
        guard let song = playerData.currentlyPlaying,
              let url = URL(string: "\(Secrets.base_url)get-mp3/" + song.mp3Url!) else { return }
        
        print(url)
        
        let playerItem = AVPlayerItem(url: url)
        self.player = AVPlayer(playerItem: playerItem)
        self.player?.play()
        playerData.isPlaying = true
    }
    
    private func togglePlay() {
        playerData.isPlaying.toggle()
        
        if playerData.isPlaying {
            self.player?.play()
        } else {
            self.player?.pause()
        }
    }
}

#Preview {
    ContentView()
}
