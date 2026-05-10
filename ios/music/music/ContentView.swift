import SwiftUI

struct ContentView: View {
    @State var playlists: [Playlist] = []
    
    var body: some View {
        NavigationStack {
            ForEach(playlists) { group in
                NavigationLink(destination: PlaylistView()) {
                    ZStack {
                        if group.image == nil {
                            EmptyView()
                        } else {
                            ZStack {
                                
                                
                                AsyncImage(url: URL(string: group.image!)) { image in
                                    image.resizable()
                                } placeholder: {
                                    ProgressView()
                                }
                                .frame(width: 100, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .blur(radius: 1)
                                
                                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                
                            }
                        }
                        Text(group.name)
                            .foregroundStyle(Color.white)
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
