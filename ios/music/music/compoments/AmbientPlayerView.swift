import SwiftUI
import AVFoundation
#if os(iOS)
import UIKit
#endif

/// Full-screen "put the phone down" experience shown when the sheet is in
/// landscape: a clock, huge artwork, an artwork-derived animated gradient, the
/// current synced lyrics (a few lines for context), and rotating per-song stat
/// cards. When an iOS Focus (e.g. Sleep) is active it shifts to a darker,
/// nighttime-friendly look with a prominent bedside clock.
struct AmbientPlayerView: View {
    @State private var manager = PlayerManager.shared
    @State private var sleep = SleepMonitor.shared
    @State private var charging = false

    var body: some View {
        let sleepActive = sleep.isActive
        // Sleep alone dims the look; sleep while charging (bedside dock at
        // night) goes darkest. Outside sleep we still gently rein in bright
        // covers so white text never lands on a near-white wash.
        let dimming: Dimming = sleepActive ? (charging ? .deep : .dim) : .none

        GeometryReader { geo in
            #if os(macOS)
            // Plenty of width on a Mac window: shrink the artwork and let the
            // lyrics dominate, Spotify-style.
            let side = max(160, geo.size.height * 0.42)
            let lyricSize: CGFloat = 46
            let titleSize: CGFloat = 34
            #else
            let side = max(120, geo.size.height * 0.6)
            let lyricSize: CGFloat = 24
            let titleSize: CGFloat = 26
            #endif

            ZStack {
                AmbientBackground(colors: manager.artworkPalette, dimming: dimming)
                    .ignoresSafeArea()

                // A constant scrim keeps the white clock/lyrics legible over a
                // bright, washed-out cover; sleep (and charging) deepen it.
                Color.black.opacity(dimming.scrimOpacity).ignoresSafeArea()

                HStack(spacing: 44) {
                    // Clock sits directly above the artwork and is capped to its
                    // width, so the time fills the image but never overruns it.
                    VStack(alignment: .leading, spacing: 4) {
                        clock(sleepActive: sleepActive)
                            .frame(width: side, alignment: .leading)
                        artwork(sleepActive: sleepActive)
                            .frame(width: side, height: side)
                    }
                    details(sleepActive: sleepActive, lyricSize: lyricSize, titleSize: titleSize)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 24)
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
        // Confine dark mode to this subtree. Using `.preferredColorScheme` here
        // would propagate up to the whole window and linger after dismissal —
        // visible as stray dark colors when leaving the ambient view on macOS.
        .environment(\.colorScheme, .dark)
        .task {
            // No focus-change notification exists, so poll while we're on screen.
            sleep.start()
            while !Task.isCancelled {
                sleep.refresh()
                try? await Task.sleep(for: .seconds(6))
            }
        }
        // Keep the screen lit (like YouTube/Netflix) while this lean-back view is
        // up — but only when plugged in, so we never drain an unattended battery.
        .onAppear {
            #if os(iOS)
            UIDevice.current.isBatteryMonitoringEnabled = true
            updateIdleTimer()
            #endif
        }
        .onDisappear {
            #if os(iOS)
            // Hand the system its normal auto-lock back when we leave.
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            updateIdleTimer()
        }
        #endif
    }

    #if os(iOS)
    /// Disable auto-lock only while charging or fully charged on power; otherwise
    /// let the device sleep normally.
    private func updateIdleTimer() {
        let state = UIDevice.current.batteryState
        let pluggedIn = state == .charging || state == .full
        charging = pluggedIn
        UIApplication.shared.isIdleTimerDisabled = pluggedIn
    }
    #endif

    private func clock(sleepActive: Bool) -> some View {
        TimelineView(.everyMinute) { context in
            Text(context.date, format: .dateTime.hour().minute())
                .font(.system(size: sleepActive ? 120 : 92, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(.white.opacity(sleepActive ? 0.92 : 0.85))
                .contentTransition(.numericText())
        }
    }

    private func artwork(sleepActive: Bool) -> some View {
        AsyncImage(url: URL(string: manager.currentlyPlaying?.imageUrl ?? "")) { image in
            image.resizable()
        } placeholder: {
            RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.1))
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
        .opacity(sleepActive ? 0.82 : 1)
        .brightness(sleepActive ? -0.08 : 0)
    }

    private func details(sleepActive: Bool, lyricSize: CGFloat, titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let song = manager.currentlyPlaying {
                Text(song.title)
                    .font(.system(size: titleSize, weight: .bold))
                    .lineLimit(2)
                if let artist = song.artist {
                    Text(artist)
                        .font(.system(size: titleSize * 0.55))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            Spacer(minLength: 0)

            lyrics(size: lyricSize)

            Spacer(minLength: 0)

            // The cycling stat cards are playful for daytime but distracting at
            // night, so hide them in sleep mode.
            if !sleepActive {
                statCards
            }

            if let song = manager.currentlyPlaying {
                seekBar(duration: song.duration)
            }

            PlayerControlsView(tint: .white, playIconColor: .black)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Scrub bar with elapsed / remaining labels, styled for the dark ambient
    /// backdrop. Mirrors the portrait sheet's seek behaviour.
    private func seekBar(duration: Int) -> some View {
        Slider(value: $manager.timeIntoSong, in: 0...Double(max(duration, 1))) {
            Text("Seek")
        } minimumValueLabel: {
            Text(numberToTime(number: manager.timeIntoSong))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
        } maximumValueLabel: {
            Text(numberToTime(number: Double(duration)))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
        } onEditingChanged: { editing in
            manager.isSeeking = editing
            if editing { return }
            manager.player?.seek(to: CMTime(value: Int64(manager.timeIntoSong), timescale: 1))
        }
        .tint(.white)
    }

    /// A short window of synced lyrics — a line of context before and after the
    /// active line — so it's clear where the song is, not just one floating line.
    @ViewBuilder
    private func lyrics(size: CGFloat) -> some View {
        let lines = manager.currentLyrics
        if !lines.isEmpty {
            let active = manager.currentLyricIndex(at: manager.timeIntoSong)
            VStack(alignment: .leading, spacing: size * 0.4) {
                ForEach(lyricWindow(lines: lines, active: active), id: \.0) { index, line in
                    Text(line.text)
                        .font(.system(size: size, weight: index == active ? .bold : .regular))
                        .foregroundStyle(index == active ? .white : .white.opacity(0.4))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.3), value: active)
        }
    }

    /// Indices (with their lines) to display: one before the active line and a
    /// couple after, clamped to the available range. Falls back to the opening
    /// lines before playback reaches the first timestamp.
    private func lyricWindow(lines: [LyricLine], active: Int?) -> [(Int, LyricLine)] {
        let center = active ?? 0
        let end = min(lines.count - 1, max(center, 0) + 2)
        let start = max(0, end - 3)
        return (start...end).map { ($0, lines[$0]) }
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

/// How dark to render the ambient backdrop.
/// - `none`: daytime — keep the artwork colours, only rein in the bright end.
/// - `dim`: an iOS Sleep/Focus is active.
/// - `deep`: Sleep active *and* charging (bedside dock) — darkest.
enum Dimming {
    case none, dim, deep

    /// Constant black scrim laid over the gradient for text legibility.
    var scrimOpacity: Double {
        switch self {
        case .none: return 0.2
        case .dim: return 0.3
        case .deep: return 0.42
        }
    }
}

/// Slowly drifting mesh gradient built from the album artwork's palette. Every
/// stop is toned toward a text-legible range so the white clock/lyrics never
/// sit on a near-white cover; sleep and charging darken it further.
struct AmbientBackground: View {
    let colors: [Color]
    var dimming: Dimming = .none
    @Environment(\.self) private var environment

    var body: some View {
        let palette = palette(for: colors)
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

    private func palette(for colors: [Color]) -> [Color] {
        resolved(colors).map { tone($0.resolve(in: environment)) }
    }

    /// Brings each stop into a legible brightness range. In daytime we only cap
    /// the bright end (so a mostly-white cover can't wash out white text);
    /// sleep pulls light colours down hard, charging hardest.
    private func tone(_ c: Color.Resolved) -> Color {
        let r = Double(c.red), g = Double(c.green), b = Double(c.blue)
        let luminance = max(0.2126 * r + 0.7152 * g + 0.0722 * b, 0.0001)
        let factor: Double
        switch dimming {
        case .none:
            // Only scale down stops brighter than ~0.55 luminance.
            factor = min(1, 0.55 / luminance)
        case .dim:
            factor = luminance > 0.5 ? 0.18 : 0.34
        case .deep:
            factor = luminance > 0.5 ? 0.10 : 0.20
        }
        return Color(red: r * factor, green: g * factor, blue: b * factor)
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
