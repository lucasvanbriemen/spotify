import SwiftUI
import AVFoundation

struct PlayerSheetView: View {
    @State private var manager = PlayerManager.shared
    // `.compact` height = landscape on iPhone. Rotating presents the ambient
    // view as a true full-screen cover (not cramped inside the sheet card).
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        portrait
            .fullScreenCover(isPresented: Binding(
                get: { verticalSizeClass == .compact && manager.hasSheetOpen },
                set: { _ in }
            )) {
                AmbientPlayerView()
            }
    }

    private var portrait: some View {
        VStack {
            if let song = manager.currentlyPlaying {
                SongListingView(song: song, bgColor: Color.clear, shouldPlaySong: false)
            }

            LyricsView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            PlayerControlsView()

            if let song = manager.currentlyPlaying {
                Slider(value: $manager.timeIntoSong, in: 0...Double(song.duration)) {
                    Text("Seek")
                } minimumValueLabel: {
                    Text(numberToTime(number: manager.timeIntoSong))
                } maximumValueLabel: {
                    Text(numberToTime(number: Double(song.duration)))
                } onEditingChanged: { editing in
                    manager.isSeeking = editing
                    if editing { return }
                    manager.player?.seek(to: CMTime(value: Int64(manager.timeIntoSong), timescale: 1))
                }
            }
        }
        .padding(16)
    }
}

/// Transport controls (shuffle / prev / play / next / repeat). Set `compact`
/// to show only the essentials (play/pause + next) for the ambient view.
struct PlayerControlsView: View {
    @State private var manager = PlayerManager.shared
    var compact: Bool = false
    var tint: Color = .accentColor
    var playIconColor: Color = .white

    var body: some View {
        HStack {
            if !compact {
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
                .foregroundStyle(manager.shouldShuffle ? tint : Color.secondary)
                .clipShape(Circle())
            }

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
            .background(tint)
            .foregroundStyle(playIconColor)
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

            if !compact {
                Button(action: {
                    manager.shouldRepeat.toggle()
                }) {
                    Image(systemName: "repeat")
                        .badge(1)
                        .font(Font.system(size: 24))
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .foregroundStyle(manager.shouldRepeat ? tint : Color.secondary)
                .clipShape(Circle())
            }
        }
    }
}

/// Synced "karaoke" lyrics that track playback, with graceful fallbacks to
/// plain lyrics or a quiet placeholder.
struct LyricsView: View {
    @State private var manager = PlayerManager.shared

    var body: some View {
        if !manager.currentLyrics.isEmpty {
            syncedLyrics
        } else if let plain = manager.plainLyrics, !plain.isEmpty {
            ScrollView {
                Text(plain)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack {
                Spacer()
                Text("No lyrics")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
    }

    private var syncedLyrics: some View {
        let activeIndex = manager.currentLyricIndex(at: manager.timeIntoSong)

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(manager.currentLyrics.enumerated()), id: \.element.id) { index, line in
                        Text(line.text)
                            .font(.title3.bold())
                            .foregroundStyle(index == activeIndex ? Color.primary : Color.secondary.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: activeIndex) { _, newIndex in
                guard let newIndex else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }
}

func numberToTime(number: Double) -> String {
    let totalSeconds = Int(number)
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60

    return String(format: "%d:%02d", minutes, seconds)
}
