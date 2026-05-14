import SwiftUI
import AVFoundation

struct PlayerSheetView: View {
    @State private var manager = PlayerManager.shared

    @State private var speed = 50.0
    @State private var isEditing = false

    
    var body: some View {
        SongListingView(song: manager.currentlyPlaying!, bgColor: Color.clear, shouldPlaySong: false)

        Slider(
                value: $manager.timeIntoSong,
                in: 0...Double(manager.currentlyPlaying!.duration),
            ) {
                Text("Speed")
            } minimumValueLabel: {
                Text("0")
            } maximumValueLabel: {
                Text(String(manager.currentlyPlaying!.duration))
            } onEditingChanged: { editing in
                manager.player?.seek(to: CMTime(value: Int64(manager.timeIntoSong), timescale: 1))
            }
            Text("\(manager.timeIntoSong)")
                .foregroundColor(isEditing ? .red : .blue)
    }
}
