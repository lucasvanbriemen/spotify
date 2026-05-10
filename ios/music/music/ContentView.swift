import SwiftUI

struct ContentView: View {
    @State var playlists: [Playlist] = []
    
    var body: some View {
        VStack {
            ForEach(playlists) { group in
                Text(group.name)

                if group.image == nil {
                    EmptyView()
                } else {
                    AsyncImage(url: URL(string: group.image!))
                    .frame(width: 100, height: 100)
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
