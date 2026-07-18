#if os(iOS)
import SwiftUI
import UIKit

/// Tracks whether the app is driving an external display (AirPlay screen
/// mirroring). Both the TV scene and the in-app ambient view need the phone
/// to stay awake — auto-lock would end the mirroring session — so the
/// idle-timer decision is centralized here instead of scattered writes that
/// could undo each other.
@Observable
class ExternalDisplayState {
    static let shared = ExternalDisplayState()
    private init() {}

    private(set) var isConnected = false

    /// Set by the in-app ambient view while it is on screen and plugged in.
    var ambientKeepAwake = false {
        didSet { refreshIdleTimer() }
    }

    func setConnected(_ connected: Bool) {
        isConnected = connected
        refreshIdleTimer()
    }

    private func refreshIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = isConnected || ambientKeepAwake
    }
}

/// Fills the external (non-interactive) scene the system hands us while
/// screen-mirroring: the TV shows the ambient player instead of a mirror of
/// the phone, and the phone keeps its normal UI.
class ExternalSceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: AmbientPlayerView(onExternalDisplay: true))
        // Non-interactive display: just unhide. makeKeyAndVisible would steal
        // key-window status from the window that receives touches.
        window.isHidden = false
        self.window = window

        ExternalDisplayState.shared.setConnected(true)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        window = nil
        ExternalDisplayState.shared.setConnected(false)
    }
}
#endif
