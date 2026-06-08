import SwiftUI

/// Full-screen "put the phone down" experience shown when the sheet is in
/// landscape: huge artwork, an artwork-derived animated gradient, the current
/// synced lyric line, and rotating per-song stat cards.
struct AmbientPlayerView: View {
    @State private var manager = PlayerManager.shared

    var body: some View {
        GeometryReader { geo in
            // Square artwork sized to the available height; details fill the rest.
            let side = max(120, geo.size.height * 0.6)

            ZStack {
                AmbientBackground(colors: manager.artworkPalette)
                    .ignoresSafeArea()

                HStack(spacing: 44) {
                    artwork
                        .frame(width: side, height: side)
                    details
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .topTrailing) {
                Button(action: { manager.hasSheetOpen = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .padding(12)
                        .background(.white.opacity(0.15), in: Circle())
                }
                .foregroundStyle(.white)
                .padding(24)
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }

    private var artwork: some View {
        AsyncImage(url: URL(string: manager.currentlyPlaying?.imageUrl ?? "")) { image in
            image.resizable()
        } placeholder: {
            RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.1))
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let song = manager.currentlyPlaying {
                Text(song.title)
                    .font(.system(size: 26, weight: .bold))
                    .lineLimit(2)
                if let artist = song.artist {
                    Text(artist)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            Spacer(minLength: 0)

            currentLyricLine

            Spacer(minLength: 0)

            statCards

            PlayerControlsView(compact: true, tint: .white, playIconColor: .black)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var currentLyricLine: some View {
        let index = manager.currentLyricIndex(at: manager.timeIntoSong)
        if let index, manager.currentLyrics.indices.contains(index) {
            Text(manager.currentLyrics[index].text)
                .font(.system(size: 26, weight: .bold))
                .lineLimit(3)
                .id(index)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.35), value: index)
        }
    }

    @ViewBuilder
    private var statCards: some View {
        if let stats = manager.currentSongStats {
            // Cycle between the two stats every 5 seconds.
            TimelineView(.periodic(from: .now, by: 5)) { context in
                let slot = Int(context.date.timeIntervalSinceReferenceDate / 5) % 2
                Group {
                    if slot == 0 {
                        AmbientStatCard(value: "\(stats.playCount)", label: stats.playCount == 1 ? "time played" : "times played")
                    } else {
                        AmbientStatCard(value: formatPlayTime(seconds: stats.secondsPlayed), label: "listened")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeInOut(duration: 0.4), value: slot)
            }
        }
    }
}

private struct AmbientStatCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 28, weight: .bold))
            Text(label)
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Slowly drifting mesh gradient built from the album artwork's palette.
struct AmbientBackground: View {
    let colors: [Color]

    var body: some View {
        let palette = resolved(colors)
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 3,
                height: 3,
                points: points(t: t),
                colors: meshColors(palette)
            )
        }
    }

    private func resolved(_ colors: [Color]) -> [Color] {
        if colors.count >= 2 { return colors }
        if colors.count == 1 { return [colors[0], colors[0].opacity(0.4)] }
        return [Color(red: 0.15, green: 0.16, blue: 0.20), Color(red: 0.06, green: 0.06, blue: 0.09)]
    }

    private func meshColors(_ palette: [Color]) -> [Color] {
        (0..<9).map { palette[$0 % palette.count] }
    }

    private func points(t: Double) -> [SIMD2<Float>] {
        let a = Float(sin(t * 0.5)) * 0.08
        let b = Float(cos(t * 0.4)) * 0.08
        return [
            SIMD2(0, 0), SIMD2(0.5 + a, 0), SIMD2(1, 0),
            SIMD2(0, 0.5 + b), SIMD2(0.5 + a, 0.5 + b), SIMD2(1, 0.5 - b),
            SIMD2(0, 1), SIMD2(0.5 - a, 1), SIMD2(1, 1)
        ]
    }
}
