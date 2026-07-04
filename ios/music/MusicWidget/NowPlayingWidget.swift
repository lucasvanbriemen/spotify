import WidgetKit
import SwiftUI
import AppIntents

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: NowPlayingSnapshot?
    let artwork: Data?
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(
            date: .now,
            snapshot: NowPlayingSnapshot(title: "Song Title", artist: "Artist", isPlaying: true),
            artwork: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        // The app pushes a reload on every state change, so a single entry
        // that never expires is enough.
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> NowPlayingEntry {
        NowPlayingEntry(
            date: .now,
            snapshot: NowPlayingSnapshot.load(),
            artwork: NowPlayingSnapshot.loadArtwork()
        )
    }
}

struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: NowPlayingSnapshot.widgetKind, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Now Playing")
        .description("See and control what's playing.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NowPlayingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: NowPlayingEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .systemMedium:
                mediumLayout(snapshot)
            default:
                smallLayout(snapshot)
            }
        } else {
            idleLayout
        }
    }

    private var idleLayout: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Nothing playing")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func smallLayout(_ snapshot: NowPlayingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                artworkView(size: 44)
                Spacer()
                playPauseButton(snapshot, size: 36)
            }
            Spacer(minLength: 8)
            titleView(snapshot)
        }
    }

    private func mediumLayout(_ snapshot: NowPlayingSnapshot) -> some View {
        HStack(spacing: 12) {
            artworkView(size: 64)
            VStack(alignment: .leading, spacing: 2) {
                titleView(snapshot)
            }
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                Button(intent: PreviousSongIntent()) {
                    Image(systemName: "backward.fill")
                        .font(.footnote)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                playPauseButton(snapshot, size: 40)
                Button(intent: NextSongIntent()) {
                    Image(systemName: "forward.fill")
                        .font(.footnote)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func titleView(_ snapshot: NowPlayingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.title)
                .font(.footnote.bold())
                .lineLimit(1)
            Text(snapshot.artist ?? "Unknown Artist")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func playPauseButton(_ snapshot: NowPlayingSnapshot, size: CGFloat) -> some View {
        Button(intent: TogglePlayPauseIntent()) {
            Image(systemName: snapshot.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .resizable()
                .frame(width: size, height: size)
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func artworkView(size: CGFloat) -> some View {
        if let data = entry.artwork, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }
        }
    }
}
