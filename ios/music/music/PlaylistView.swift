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
        VStack {
            if !isLoading, let playlist {
                VStack {
                    Text(playlist.name)
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
        } catch {
            print(error)
        }
    }
}
