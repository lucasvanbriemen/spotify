import SwiftUI

/// Grid of server-curated radio stations. Tapping a card tunes in (or toggles
/// play/pause when the station is already on air) — no track list to browse,
/// the station programs itself.
struct StationsView: View {
    @State var stations: [Station] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading) {
                    Text("Radio")
                        .fontWeight(.bold)
                        .padding([.top, .leading], 16)
                    #if !os(macOS)
                        .foregroundStyle(Color(.label))
                    #else
                        .foregroundStyle(Color(NSColor.controlBackgroundColor))
                    #endif

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))]) {
                        ForEach(stations) { station in
                            StationCardView(station: station)
                        }
                    }
                }
            }
            .padding([.leading, .trailing], 8)
        }

        .task {
            await getStations()
        }
    }

    func getStations() async {
        let response: StationsResponse? = await ServerApi.get(endpoint: "stations")
        stations = response?.stations ?? []
    }
}

struct StationCardView: View {
    let station: Station
    @State private var manager = PlayerManager.shared

    var body: some View {
        Button {
            if manager.currentStation?.id == station.id {
                manager.togglePlayPause()
            } else {
                manager.playStation(station: station)
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                PlaylistBackgroundView(imageUrl: station.image, height: 160)

                Text(station.name)
                    .foregroundStyle(Color.white)
                    .font(Font.title2.bold())
                    .lineLimit(2)
                    .padding(12)
            }
            .overlay(alignment: .topTrailing) {
                if manager.isCurrentlyPlayingStation(station.id) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.4), in: Circle())
                        .padding(12)
                }
            }
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
    }
}

#Preview {
    StationsView()
}
