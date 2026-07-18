import SwiftUI
import AVKit

/// The system AirPlay output picker (TVs, HomePods, Bluetooth speakers),
/// styled to sit alongside the transport buttons.
#if os(macOS)
struct RoutePickerView: NSViewRepresentable {
    var tint: Color = .accentColor

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        view.setRoutePickerButtonColor(NSColor(tint), for: .active)
        return view
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {
        nsView.setRoutePickerButtonColor(NSColor(tint), for: .active)
    }
}
#else
struct RoutePickerView: UIViewRepresentable {
    var tint: Color = .accentColor

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.tintColor = UIColor.secondaryLabel
        view.activeTintColor = UIColor(tint)
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.activeTintColor = UIColor(tint)
    }
}
#endif
