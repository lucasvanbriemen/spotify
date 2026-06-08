import SwiftUI

struct StatsView: View {
    @State var stats: Stats?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading) {
                    Text("All time")
                        .fontWeight(.bold)
                        .padding([.top, .leading], 16)
                    #if os(iOS)
                        .foregroundStyle(Color(.label))
                    #else
                        .foregroundStyle(Color(NSColor.controlBackgroundColor))
                    #endif

                    if let stats {
                        HStack(spacing: 8) {
                            StatCardView(value: "\(stats.uniqueSongs)", label: "Different songs")
                            StatCardView(value: formatPlayTime(seconds: stats.totalSecondsPlayed), label: "Played time")
                            StatCardView(value: "\(stats.totalPlays)", label: "Plays")
                        }

                        if !stats.topSongs.isEmpty {
                            Text("Top songs")
                                .fontWeight(.bold)
                                .padding([.top, .leading], 16)

                            ForEach(Array(stats.topSongs.enumerated()), id: \.element.id) { index, song in
                                TopSongListingView(rank: index + 1, song: song)
                            }
                        }
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 64)
                    }
                }
            }
            .padding([.leading, .trailing], 8)
        }
        .task {
            await getStats()
        }
        .refreshable {
            await getStats()
        }
    }

    func getStats() async {
        stats = await ServerApi.get(endpoint: "stats")
    }
}

func formatPlayTime(seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60

    if hours > 0 {
        return "\(hours)h \(minutes)m"
    }
    return "\(minutes)m"
}

struct StatCardView: View {
    let value: String
    let label: String

    var body: some View {
        VStack {
            Text(value)
                .font(Font.title2.bold())
            Text(label)
                .font(Font.system(size: 12, weight: .light, design: .default))
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.gray.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct TopSongListingView: View {
    let rank: Int
    let song: TopSong

    var body: some View {
        HStack(alignment: .center) {
            Text("\(rank)")
                .font(Font.title3.bold())
                .frame(width: 24)

            AsyncImage(url: URL(string: song.imageUrl ?? "")) { image in
                image.resizable()
            } placeholder: {
                ProgressView()
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading) {
                Text(song.title)
                    .fontWeight(Font.Weight.bold)
                    .frame(height: 18)
                    .truncationMode(.tail)
                Text(song.artist)
                    .font(Font.system(size: 14, weight: .light, design: .default))
                    .frame(height: 18)
                    .truncationMode(.tail)
            }

            Spacer()

            Text("\(song.playCount) plays")
                .font(Font.system(size: 14, weight: .light, design: .default))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .foregroundStyle(Color.primary)
    }
}

#Preview {
    StatsView()
}
