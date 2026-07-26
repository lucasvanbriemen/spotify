import SwiftUI

/// Detail pane for a radio station (reached from the macOS sidebar): a
/// playlist-style header with art and a play control, and — while the station
/// is on air — a peek at the next few items the server has queued up.
struct StationDetailView: View {
    let station: Station
    @State private var manager = PlayerManager.shared

    private var isCurrent: Bool {
        manager.currentStation?.id == station.id
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                HStack(alignment: .bottom, spacing: 20) {
                    PlaylistBackgroundView(imageUrl: station.image, height: 168)
                        .frame(width: 168)
                        .shadow(color: .black.opacity(0.25), radius: 14, y: 8)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(station.name)
                            .font(.system(size: 32, weight: .bold))
                            .lineLimit(2)
                            .truncationMode(.tail)
                        Text("LTVB Radio")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button(action: {
                            if !isCurrent {
                                manager.playStation(station: station)
                            }
                        }) {
                            Label(
                                isCurrent ? "On Air" : "Listen Live",
                                systemImage: isCurrent ? "dot.radiowaves.left.and.right" : "play.fill"
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isCurrent)
                        .controlSize(.large)
                        .padding(.top, 10)
                    }
                    .padding(.bottom, 4)

                    Spacer(minLength: 0)
                }
                .padding(.top, 16)
                .padding(.bottom, 12)

                if isCurrent {
                    Text("Up next")
                        .font(.headline)
                        .padding(.bottom, 4)

                    #if os(macOS)
                    let secondaryColor = Color.primary.opacity(0.045)
                    #else
                    let secondaryColor = Color(.secondarySystemBackground)
                    #endif

                    ForEach(Array(manager.queue.prefix(10).enumerated()), id: \.element.id) { index, song in
                        let bg: Color = index.isMultiple(of: 2) ? .clear : secondaryColor
                        SongListingView(song: song, bgColor: bg, shouldPlaySong: false)
                    }
                }
            }
            .padding([.leading, .trailing], 20)
        }
        #if os(macOS)
        .navigationTitle(station.name)
        #endif
    }
}
