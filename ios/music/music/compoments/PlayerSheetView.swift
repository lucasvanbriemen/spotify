import SwiftUI

struct PlayerSheetView: View {
    var manager = PlayerManager.shared
    
    var body: some View {
        SongListingView(song: manager.currentlyPlaying!, bgColor: Color.clear, shouldPlaySong: false)
    }
}
