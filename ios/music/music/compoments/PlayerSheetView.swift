import SwiftUI
import AVFoundation

struct PlayerSheetView: View {
    @State private var manager = PlayerManager.shared
    
    var body: some View {
        VStack {
            SongListingView(song: manager.currentlyPlaying!, bgColor: Color.clear, shouldPlaySong: false)
            
            Spacer()
            
            HStack {
                Button(action: {
                    manager.shouldShuffle.toggle()
                    manager.applySuffle()
                }) {
                    Image(systemName: "shuffle")
                        .badge(1)
                        .font(Font.system(size: 24))
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .foregroundStyle(manager.shouldShuffle ? Color.accentColor : Color.secondary)
                .clipShape(Circle())
                
                Button(action: { manager.playPreviousSong() }) {
                    Image(systemName: "arrowtriangle.down.2.fill")
                        .font(Font.system(size: 24))
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .foregroundStyle(Color.secondary)
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
                        .font(Font.system(size: 24))
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .foregroundStyle(Color.secondary)
                .clipShape(Circle())
                .rotationEffect(Angle(degrees: 90))
                
                Button(action: {
                    manager.shouldShuffle.toggle()
                    manager.applySuffle()
                }) {
                    Image(systemName: "repeat")
                        .badge(1)
                        .font(Font.system(size: 24))
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .foregroundStyle(manager.shouldShuffle ? Color.accentColor : Color.secondary)
                .clipShape(Circle())
            }
            
            Slider(value: $manager.timeIntoSong, in: 0...Double(manager.currentlyPlaying!.duration)) {
                Text("Seek")
            } minimumValueLabel: {
                Text(numberToTime(number: manager.timeIntoSong))
            } maximumValueLabel: {
                Text(numberToTime(number: Double(manager.currentlyPlaying!.duration)))
            } onEditingChanged: { editing in
                manager.isSeeking = editing
                if editing { return }
                manager.player?.seek(to: CMTime(value: Int64(manager.timeIntoSong), timescale: 1))
            }
        }
        .padding(16)
    }
    
    func numberToTime(number: Double) -> String {
        let totalSeconds = Int(number)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        
        return String(format: "%d:%02d", minutes, seconds)
    }
}

