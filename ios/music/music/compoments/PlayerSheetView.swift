import SwiftUI
import AVFoundation

struct PlayerSheetView: View {
    @State private var manager = PlayerManager.shared
    
    var body: some View {
        SongListingView(song: manager.currentlyPlaying!, bgColor: Color.clear, shouldPlaySong: false)

        
        HStack {
            Button(action: { manager.playPreviousSong() }) {
                Image(systemName: "arrowtriangle.down.2.fill")
                    .font(Font.system(size: 32))
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .background(Color.accentColor)
            .foregroundStyle(Color.white)
            .clipShape(Circle())
            .rotationEffect(Angle(degrees: 90))
            
            
            Button(action: { manager.togglePlayPause() }) {
                Image(systemName: manager.isPlaying ? "pause" : "play")
                    .font(Font.system(size: 32))
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .background(Color.accentColor)
            .foregroundStyle(Color.white)
            .clipShape(Circle())
            
            Button(action: { manager.playNextSong() }) {
                Image(systemName: "arrowtriangle.up.2.fill")
                    .font(Font.system(size: 32))
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .background(Color.accentColor)
            .foregroundStyle(Color.white)
            .clipShape(Circle())
            .rotationEffect(Angle(degrees: 90))
        }
        
        
        
        Slider(value: $manager.timeIntoSong, in: 0...Double(manager.currentlyPlaying!.duration)) {
            Text("Seek")
        } minimumValueLabel: {
            Text("0")
        } maximumValueLabel: {
            Text(String(manager.currentlyPlaying!.duration))
        } onEditingChanged: { editing in
            manager.isSeeking = editing
            if editing { return }
            manager.player?.seek(to: CMTime(value: Int64(manager.timeIntoSong), timescale: 1))
        }
    }
}

