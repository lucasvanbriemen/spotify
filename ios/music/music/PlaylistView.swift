import SwiftUI
import Foundation

struct PlaylistView: View {
    @State var playlistID: Int = 1
    @State var playlist: Playlist?
    
    init(playlistID: Int) {
        self.playlistID = playlistID
    }
    
    var body: some View {
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
        
            .task {
                await getPlaylist()
            }
    }
    
    
    func getPlaylist() async {
        do {
            playlist = try await SeverApi.get(endpoint: "playlist/\(playlistID)")
            print("get playlist")
        } catch {
            print(error)
        }
    }
}
