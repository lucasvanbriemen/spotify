import SwiftUI

@main
struct musicApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .safeAreaInset(edge: .bottom) {
                    PlayerView()
                        .padding(.bottom, -16)
                }
        }
    }
}
