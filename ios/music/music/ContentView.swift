import SwiftUI

struct ContentView: View {
    @State var playlists: [Playlist] = []
    
    var body: some View {
        NavigationStack {
            ForEach(playlists) { group in
                NavigationLink(destination: PlaylistView()) {
                    Text(group.name)
                    
                    if group.image == nil {
                        EmptyView()
                    } else {
                        AsyncImage(url: URL(string: group.image!)) { image in
                            image.resizable()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        
        .task {
            await getPlaylists()
        }
    }
    
    func getPlaylists() async {
        do {
            playlists = try await SeverApi.get(endpoint: "playlists")
            print(playlists)
        } catch {
            print("Cant get playlist: \(error)")
        }
    }
}




#Preview {
    ContentView()
}
