import SwiftUI

@main
struct musicApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .safeAreaInset(edge: .bottom) {
                    if PlayerManager.shared.currentlyPlaying != nil {
                        PlayerView()
                            .padding(.bottom, -16)
                    }
                }
        }
    }
}
