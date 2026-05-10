import SwiftUI

struct ContentView: View {
    @State var playlists: [Playlist] = []
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading) {

                    Text("Playlists")
                        .fontWeight(.bold)
                        .padding(.leading, 16)
                        .padding(.top, 16)
                        .foregroundStyle(Color(.label))

                    ForEach(playlists) { playlist in
                        NavigationLink(destination: PlaylistView()) {
                            ZStack(alignment: .bottomLeading) {
                                ZStack {
                                    AsyncImage(url: URL(string: playlist.image!)) { image in
                                        image.resizable()
                                            .blur(radius: 1)
                                    } placeholder: {
                                        ProgressView()
                                    }

                                    LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                                        
                                }
                                    .frame(width: 400, height: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 32))

                                Text(playlist.name)
                                    .foregroundStyle(Color.white)
                                    .font(Font.largeTitle.bold())
                                    .padding(16)
                            }
                        }
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
