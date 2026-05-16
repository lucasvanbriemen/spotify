import SwiftUI

struct PlayerSheetView: View {
    @State private var manager = PlayerManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let song = manager.currentlyPlaying {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 28) {
                    AsyncImage(url: URL(string: song.imageUrl ?? "")) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(maxWidth: 360, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 24, y: 8)

                    VStack(spacing: 6) {
                        Text(song.title)
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                        Text(song.artist ?? "")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        if let album = song.album {
                            Text(album)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 32)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(10)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .padding(16)
            }
            #if os(macOS)
            .frame(minWidth: 520, idealWidth: 640, minHeight: 640, idealHeight: 760)
            #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
            .background(.regularMaterial)
        }
    }
}
