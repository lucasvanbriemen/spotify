import SwiftUI
import AVFoundation
import MediaPlayer

struct PlayerView: View {
    var body: some View {
        HStack(alignment: .center) {
            if let song = PlayerManager.currentlyPlaying {
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
                
                Button(action: { togglePlay() }) {
                    Image(systemName: PlayerManager.isPlaying ? "pause" : "play")
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
        .onChange(of: PlayerManager.currentlyPlaying?.id) {
            play()
            updateNowPlayingInfo()
        }
        .padding([.leading, .trailing], 8)
        .frame(width: 390, height: 64)
        .background(Color(red: 0.11, green: 0.73, blue: 0.33))
        .clipShape(Capsule())
    }

    private func play() {
        PlayerManager.player?.pause()
        PlayerManager.isPlaying = false
        
        guard let song = PlayerManager.currentlyPlaying,
              let url = URL(string: "\(Secrets.base_url)get-mp3/" + song.mp3Url!) else { return }
        
        print(url)
        
        let playerItem = AVPlayerItem(url: url)
        PlayerManager.player = AVPlayer(playerItem: playerItem)
        PlayerManager.player?.play()
        PlayerManager.isPlaying = true
    }
    
    private func togglePlay(shouldPlay: Bool? = nil) {
        if shouldPlay == nil {
            PlayerManager.isPlaying.toggle()
        } else {
            PlayerManager.isPlaying = shouldPlay!
        }

        if PlayerManager.isPlaying {
            PlayerManager.player?.play()
        } else {
            PlayerManager.player?.pause()
        }
        updateNowPlayingInfo()
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
            togglePlay(shouldPlay: true)
            return .success
        }

        commandCenter.pauseCommand.addTarget { _ in
            togglePlay(shouldPlay: false)
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let song = PlayerManager.currentlyPlaying else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: song.name,
            MPMediaItemPropertyArtist: song.artist ?? "Unknown Artist",
            MPNowPlayingInfoPropertyPlaybackRate: PlayerManager.isPlaying ? 1.0 : 0.0
        ]
    }
}

#Preview {
    ContentView()
}
