import SwiftUI

struct SongMenuView: View {
    let song: Song
    @State private var playlistMap: [String: PlaylistEntry] = [:]

    var body: some View {
        Menu {
            ForEach(playlistMap.sorted(by: { $0.key < $1.key }), id: \.key) { id, entry in
                Button {
                    Task { await addToPlaylist(id: id) }
                } label: {
                    Label(entry.name, systemImage: entry.contains ? "checkmark" : "plus")
                }
                .disabled(entry.contains)
            }
        } label: {
            Image(systemName: "ellipsis")
                .rotationEffect(Angle(degrees: 90))
                .padding(10)
        }
        #if os(macOS)
        // Keep the ellipsis a quiet glyph instead of a bezeled popup button.
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(Color.secondary)
        #endif
        .onAppear {
            playlistMap = song.isInPlaylistMap ?? [:]
        }
    }

    private func addToPlaylist(id: String) async {
        let body: [String: Any] = [
            "isrc": song.isrc
        ]

        let result: Song? = await ServerApi.post(endpoint: "playlist/\(id)/songs", body: body)
        if result != nil, var entry = playlistMap[id] {
            entry.contains = true
            playlistMap[id] = entry
        }
    }
}
