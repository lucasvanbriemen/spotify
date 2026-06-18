import SwiftUI

struct NavigationView: View {

    @State var playlists: [Playlist] = []
    @State var selectedPlaylistId: String?
    @State private var manager = PlayerManager.shared
    #if os(iOS)
    // Landscape on iPhone reports a `.compact` vertical size class. Read it here
    // at the stable root (not inside a presented sheet) so rotation reliably
    // switches between the portrait sheet and the full-screen ambient view.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    var body: some View {
        #if os(iOS)
        TabView {
            Tab("Playlists", systemImage: "play.square.stack", content: { PlaylistOverviewView() })
            Tab("Stats", systemImage: "chart.bar", content: { StatsView() })
            Tab(role: .search, content: { SearchView() })
        }
        .tabViewBottomAccessory(isEnabled: PlayerManager.shared.currentlyPlaying != nil, content: { PlayerView() })
        .sheet(isPresented: PlayerManager.shared.hasSheetOpen, content: {PlayerSheetView() })
        .tabBarMinimizeBehavior(TabBarMinimizeBehavior.onScrollDown)
        // Presentations are anchored to the TabView (a stable view), not to the
        // bottom-accessory PlayerView, so they persist across song changes. The
        // single `hasSheetOpen` flag is the source of truth; size class decides
        // whether "open" means the portrait sheet or the landscape ambient view.
        .sheet(isPresented: portraitSheetBinding) { PlayerSheetView() }
        .fullScreenCover(isPresented: ambientCoverBinding) { AmbientPlayerView() }
        #else
        NavigationSplitView() {
            List {
                Section(header: Text("Playlists")) {
                    ForEach(playlists) { playlist in
                        Button {
                            selectedPlaylistId = playlist.id
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                PlaylistBackgroundView(playlist: playlist, height: 100)
                                Text(playlist.name)
                                    .foregroundStyle(Color.white)
                                    .font(Font.largeTitle.bold())
                                    .padding(16)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 32)
                                    .strokeBorder(Color.accentColor, lineWidth: selectedPlaylistId == playlist.id ? 5 : 0)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowBackground(Color.clear)
                    }
                }

                Section(header: Text("Search")) {
                    NavigationLink {
                        SearchView()
                    } label: {
                        Text("Search")
                    }
                }

                Section(header: Text("Stats")) {
                    NavigationLink {
                        StatsView()
                    } label: {
                        Text("Stats")
                    }
                }

            }
        } detail: {
            if let selectedPlaylistId {
                PlaylistView(playlistID: selectedPlaylistId)
            } else {
                ContentUnavailableView {
                    Label("Open playlist to play music", systemImage: "music.note.slash")
                } description: {
                    Text("Open a playlist in the sidebar to start playing some fire music!!")
                }
            }
        }
        // The split view has no tab-bar accessory, so dock a glass mini-player
        // pill at the bottom, matching the macOS look.
        .safeAreaInset(edge: .bottom) {
            if manager.currentlyPlaying != nil {
                PlayerView()
                    .glassEffect()
                    .padding(12)
            }
        }
        .task {
            await getPlaylists()
        }
        // macOS has no rotation, but its window is wide like a phone held in
        // landscape — so the player opens straight into the full ambient view
        // (what mobile shows on rotate) instead of a cramped portrait sheet.
        .overlay {
            if manager.hasSheetOpen {
                AmbientPlayerView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: manager.hasSheetOpen)
        #endif
    }

    #if os(iOS)
    private var isLandscape: Bool { verticalSizeClass == .compact }

    // Portrait: the player is the bottom sheet. Dismissing it (swipe down)
    // clears the shared flag; rotating to landscape just hands off to the cover.
    private var portraitSheetBinding: Binding<Bool> {
        Binding(
            get: { manager.hasSheetOpen && !isLandscape },
            set: { isOpen in if !isOpen { manager.hasSheetOpen = false } }
        )
    }

    // Landscape: the player is the full-screen ambient cover (AmbientPlayerView
    // owns its own close button, which clears the flag).
    private var ambientCoverBinding: Binding<Bool> {
        Binding(
            get: { manager.hasSheetOpen && isLandscape },
            set: { isOpen in if !isOpen { manager.hasSheetOpen = false } }
        )
    }
    #endif

    func getPlaylists() async {
        playlists = await ServerApi.get(endpoint: "playlists") ?? []
    }
}
