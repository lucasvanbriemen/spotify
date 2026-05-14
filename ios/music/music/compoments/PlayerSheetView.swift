import SwiftUI

struct PlayerSheetView: View {
    var manager = PlayerManager.shared
    
    var body: some View {
        Text(manager.currentlyPlaying?.title ?? "No song is playing")
    }
}
