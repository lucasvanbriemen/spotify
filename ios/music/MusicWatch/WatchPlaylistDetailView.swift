import SwiftUI

struct WatchPlaylistDetailView: View {
    let playlistId: String

    @State private var playlist: Playlist?
    @State private var showNowPlaying = false
    @State private var player = WatchPlayerManager.shared

    var body: some View {
        Group {
            if let playlist {
                List {
                    Button {
                        player.playPlaylist(playlist)
                        showNowPlaying = true
                    } label: {
                        Label(player.shouldShuffle ? "Shuffle All" : "Play All", systemImage: player.shouldShuffle ? "shuffle" : "play.fill")
                    }

                    Toggle(isOn: Binding(
                        get: { player.shouldShuffle },
                        set: { player.shouldShuffle = $0 }
                    )) {
                        Label("Shuffle", systemImage: "shuffle")
                    }

                    ForEach(playlist.songs ?? []) { song in
                        Button {
                            player.playPlaylist(playlist, startingAt: song)
                            showNowPlaying = true
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(song.title)
                                    .font(.footnote)
                                    .lineLimit(1)
                                Text(song.artist ?? "Unknown Artist")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .navigationDestination(isPresented: $showNowPlaying) {
            WatchNowPlayingView()
        }
        .task {
            playlist = await ServerApi.get(endpoint: "playlist/\(playlistId)")
        }
    }
}
