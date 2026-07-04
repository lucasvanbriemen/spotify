import SwiftUI

struct WatchPlaylistsView: View {
    @State private var playlists: [Playlist] = []
    @State private var isLoading = true
    @State private var player = WatchPlayerManager.shared

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if playlists.isEmpty {
                    Text("No playlists")
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(playlists) { playlist in
                            NavigationLink {
                                WatchPlaylistDetailView(playlistId: playlist.id)
                            } label: {
                                WatchPlaylistRow(playlist: playlist)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Playlists")
            .toolbar {
                if player.currentlyPlaying != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            WatchNowPlayingView()
                        } label: {
                            Image(systemName: "waveform")
                        }
                    }
                }
            }
            .task {
                playlists = await ServerApi.get(endpoint: "playlists") ?? []
                isLoading = false
            }
        }
    }
}

struct WatchPlaylistRow: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: 8) {
            AsyncImage(url: URL(string: playlist.image ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "music.note.list")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(playlist.name)
                    .font(.footnote)
                    .lineLimit(1)
                if let count = playlist.trackCount {
                    Text("\(count) songs")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
