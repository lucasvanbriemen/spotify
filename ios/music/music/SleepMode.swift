import Foundation
import Intents

/// Tracks whether the user currently has an iOS Focus enabled, which we treat
/// as "sleep mode" for the ambient player (darker palette, prominent clock).
///
/// iOS gives no signal specifically for the *Sleep* Focus and never pushes
/// focus-change events to third parties, so we poll `INFocusStatusCenter`
/// while the ambient view is on screen. `isFocused` is true whenever *any*
/// Focus is active — the best proxy the platform allows.
@Observable
class SleepMonitor {
    static let shared = SleepMonitor()
    private init() {}

    /// True when a Focus is active and we're authorized to read it.
    private(set) var isActive = false
    private var authorized = false
    private var requested = false

    /// Ask for authorization once, then sync the current state. Safe to call
    /// repeatedly (e.g. every time the ambient view appears).
    func start() {
        switch INFocusStatusCenter.default.authorizationStatus {
        case .authorized:
            authorized = true
            refresh()
        case .notDetermined where !requested:
            requested = true
            INFocusStatusCenter.default.requestAuthorization { [weak self] status in
                Task { @MainActor in
                    self?.authorized = (status == .authorized)
                    self?.refresh()
                }
            }
        default:
            authorized = false
            isActive = false
        }
    }

    /// Re-read the live focus status. Called on a short timer by the view.
    func refresh() {
        guard authorized else {
            if isActive { isActive = false }
            return
        }
        let focused = INFocusStatusCenter.default.focusStatus.isFocused ?? false
        if focused != isActive { isActive = focused }
    }
}
