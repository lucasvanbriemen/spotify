import SwiftUI
import AVFoundation
import MediaPlayer

struct PlayerView: View {
    @State private var manager = PlayerManager.shared

    var body: some View {
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
                        .frame(width: .infinity, height: 16)
                        .truncationMode(.tail)
                    Text(song.artist!)
                        .font(Font.system(size: 14, weight: .light, design: .default))
                        .frame(width: .infinity, height: 14)
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
            } else {
                EmptyView()
            }
        }
        .onAppear {
            configureAudioSession()
            setupRemoteCommands()
        }
        .onChange(of: manager.currentlyPlaying?.id) {
            play()
            updateNowPlayingInfo()
        }
        .padding([.leading, .trailing], 8)
        .frame(width: 390, height: 64)
        .background(Color(red: 0.11, green: 0.73, blue: 0.33))
        .clipShape(Capsule())
    }

    private func play() {
        manager.player?.pause()
        manager.isPlaying = false

        guard let song = manager.currentlyPlaying,
              let url = URL(string: "\(Secrets.base_url)get-mp3/" + song.mp3Url!) else { return }

        print(url)

        let playerItem = AVPlayerItem(url: url)
        manager.player = AVPlayer(playerItem: playerItem)
        manager.player?.play()
        manager.isPlaying = true
        print("play")
    }

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .moviePlayback)
            try audioSession.setActive(true)
        } catch {
            print("Failed to set the audio session configuration")
        }
    }

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { _ in
            manager.togglePlayPause(forceState: true)
            return .success
        }

        commandCenter.pauseCommand.addTarget { _ in
            manager.togglePlayPause(forceState: false)
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let song = manager.currentlyPlaying else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: song.name,
            MPMediaItemPropertyArtist: song.artist ?? "Unknown Artist",
            MPNowPlayingInfoPropertyPlaybackRate: manager.isPlaying ? 1.0 : 0.0
        ]
    }
}

#Preview {
    ContentView()
}
