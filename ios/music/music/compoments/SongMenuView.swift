import SwiftUI

struct SongMenuView: View {
    let song: Song
    
    var body: some View {
        
        Menu() {
            Button("Duplicate", action: { print("Duplicate") })
        } label: {
            Image(systemName: "ellipsis")
                .rotationEffect(Angle(degrees: 90))
        }
    }
}
