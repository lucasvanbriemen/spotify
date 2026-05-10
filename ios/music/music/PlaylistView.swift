import SwiftUI
import Foundation

struct PlaylistView: View {
    @State var playlistID: Int
    @State var playlist: Playlist?
    @State var isLoading: Bool = true
    
    init(playlistID: Int) {
        self.playlistID = playlistID
    }
    
    var body: some View {
        LazyVStack {
            if !isLoading, let playlist {
                Text(playlist.name)

                ForEach(playlist.songs ?? []) { song in
                    Text(song.name)
                }
            }
        }
        .task {
            await getPlaylist()
        }
    }
    
    
    func getPlaylist() async {
        do {
            playlist = try await SeverApi.get(endpoint: "playlist/\(String(playlistID))")
            isLoading = false
            print(playlist?.songs?.count ?? 0)
        } catch {
            print(error)
        }
    }
}
