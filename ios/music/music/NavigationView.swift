import SwiftUI

struct NavigationView: View {
    /// What the macOS sidebar can select: a fixed library entry or a playlist.
    enum SidebarItem: Hashable {
        case search
        case stats
        case playlist(String)
    }

    @State var playlists: [Playlist] = []
    @State private var sidebarSelection: SidebarItem?
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
        .tabBarMinimizeBehavior(TabBarMinimizeBehavior.onScrollDown)
        // Presentations are anchored to the TabView (a stable view), not to the
        // bottom-accessory PlayerView, so they persist across song changes. The
        // single `hasSheetOpen` flag is the source of truth; size class decides
        // whether "open" means the portrait sheet or the landscape ambient view.
        .sheet(isPresented: portraitSheetBinding) { PlayerSheetView() }
        .fullScreenCover(isPresented: ambientCoverBinding) { AmbientPlayerView() }
        #else
        // A standard macOS source-list sidebar: compact rows with a small
        // artwork thumbnail, native selection highlight, and the fixed
        // library entries grouped above the playlists.
        NavigationSplitView() {
            List(selection: $sidebarSelection) {
                Section("Library") {
                    Label("Search", systemImage: "magnifyingglass")
                        .tag(SidebarItem.search)
                    Label("Stats", systemImage: "chart.bar")
                        .tag(SidebarItem.stats)
                }

                Section("Playlists") {
                    ForEach(playlists) { playlist in
                        Label {
                            Text(playlist.name)
                        } icon: {
                            SidebarArtworkView(url: playlist.image)
                        }
                        .tag(SidebarItem.playlist(playlist.id))
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            switch sidebarSelection {
            case .search:
                SearchView()
            case .stats:
                StatsView()
            case .playlist(let id):
                PlaylistView(playlistID: id)
                    .id(id) // rebuild (and refetch) when switching playlists
            case nil:
                ContentUnavailableView {
                    Label("Open playlist to play music", systemImage: "music.note.slash")
                } description: {
                    Text("Open a playlist in the sidebar to start playing some fire music!!")
                }
            }
        }
        // The split view has no tab-bar accessory, so float a glass mini-player
        // pill at the bottom. Capped in width so it reads as a pill, not a bar.
        .safeAreaInset(edge: .bottom) {
            if manager.currentlyPlaying != nil {
                PlayerView()
                    .frame(maxWidth: 440)
                    .glassEffect()
                    .padding(.bottom, 12)
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

#if os(macOS)
/// Small rounded playlist artwork used in the sidebar rows.
private struct SidebarArtworkView: View {
    let url: String?

    var body: some View {
        AsyncImage(url: URL(string: url ?? "")) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            RoundedRectangle(cornerRadius: 5).fill(.quaternary)
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
#endif
