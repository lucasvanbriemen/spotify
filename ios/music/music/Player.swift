import SwiftUI
import AVFoundation
import MediaPlayer

struct PlayerView: View {
    @State private var manager = PlayerManager.shared

    var body: some View {
        Group {
            if let song = manager.currentlyPlaying {
                #if os(macOS)
                macBar(song: song)
                #else
                iOSBar(song: song)
                #endif
            }
        }
        .sheet(isPresented: $manager.hasSheetOpen, content: { PlayerSheetView() })
    }

    private func artwork(song: Song, size: CGFloat) -> some View {
        AsyncImage(url: URL(string: song.imageUrl ?? "")) { image in
            image.resizable()
        } placeholder: {
            ProgressView()
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func titleArtist(song: Song) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(song.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(song.artist ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func timeString(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - iOS bar (compact, opens sheet for controls)
    @ViewBuilder
    private func iOSBar(song: Song) -> some View {
        Button(action: { manager.hasSheetOpen.toggle() }) {
            HStack(alignment: .center) {
                artwork(song: song, size: 32)
                titleArtist(song: song)
                    .foregroundStyle(Color.primary)
                Spacer()
                Button(action: { manager.togglePlayPause() }) {
                    Image(systemName: manager.isPlaying ? "pause" : "play")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.secondary)
                        .padding(16)
                }
            }
            .padding(8)
        }
    }

    // MARK: - macOS bar (full controls + scrubber inline)
    #if os(macOS)
    @ViewBuilder
    private func macBar(song: Song) -> some View {
        HStack(spacing: 16) {
            Button(action: { manager.hasSheetOpen.toggle() }) {
                HStack(spacing: 10) {
                    artwork(song: song, size: 44)
                    titleArtist(song: song)
                }
            }
            .buttonStyle(.plain)
            .frame(minWidth: 180, maxWidth: 260, alignment: .leading)

            Spacer(minLength: 8)

            VStack(spacing: 6) {
                transportControls
                scrubber(song: song)
            }
            .frame(maxWidth: 520)

            Spacer(minLength: 8)

            Button(action: { manager.hasSheetOpen.toggle() }) {
                Image(systemName: "rectangle.expand.vertical")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 60, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var transportControls: some View {
        HStack(spacing: 18) {
            Button(action: {
                manager.shouldShuffle.toggle()
                manager.applySuffle()
            }) {
                Image(systemName: "shuffle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(manager.shouldShuffle ? Color.accentColor : Color.secondary)
            }

            Button(action: { manager.playPreviousSong() }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary)
            }

            Button(action: { manager.togglePlayPause() }) {
                Image(systemName: manager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .glassEffect(.regular.interactive(), in: Circle())

            Button(action: { manager.playNextSong() }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary)
            }

            Button(action: { manager.shouldRepeat.toggle() }) {
                Image(systemName: "repeat")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(manager.shouldRepeat ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func scrubber(song: Song) -> some View {
        HStack(spacing: 8) {
            Text(timeString(manager.timeIntoSong))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)

            Slider(
                value: $manager.timeIntoSong,
                in: 0...max(Double(song.duration), 1),
                onEditingChanged: { editing in
                    manager.isSeeking = editing
                    if editing { return }
                    manager.player?.seek(to: CMTime(value: Int64(manager.timeIntoSong), timescale: 1))
                }
            )
            .controlSize(.mini)

            Text(timeString(Double(song.duration)))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
        }
    }
    #endif
}
