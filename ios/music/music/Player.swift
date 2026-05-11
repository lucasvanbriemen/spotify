import SwiftUI
import AVFoundation

struct PlayerView: View {
    @State private var player: AVPlayer?
    private let playerData = PlayerData.shared
    @State private var timer = 0.0

    var body: some View {
        HStack {
            if let song = playerData.currentlyPlaying {
                Text(song.name)
            } else {
                Text("Nothing playing")
                    .foregroundStyle(.secondary)
            }
            
            Slider(value: $timer, in: 0...100, onEditingChanged: {editing in
                print(String(timer))
            })
        }
        .onChange(of: playerData.currentlyPlaying?.id) {
            play()
        }
    }

    private func play() {
        
        self.player?.pause()
        
        guard let song = playerData.currentlyPlaying,
              let url = URL(string: "\(Secrets.base_url)get-mp3/" + song.mp3Url!) else { return }
        
        print(url)
        
        let playerItem = AVPlayerItem(url: url)
        self.player = AVPlayer(playerItem: playerItem)
        self.player?.play()
    }
}

#Preview {
    ContentView()
}
