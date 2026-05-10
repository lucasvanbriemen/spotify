import SwiftUI
import AVFoundation

struct PlayerView: View {
    
    @State var player: AVPlayer?
    
    var body: some View {
        Button("play") {
            guard let url = URL(string: Secrets.test_song) else { return }
            let playerItem = AVPlayerItem(url: url)
            self.player = AVPlayer(playerItem: playerItem)
            self.player?.play()
        }
    }
    
    
}

#Preview {
    ContentView()
}
