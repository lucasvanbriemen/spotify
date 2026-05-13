import SwiftUI

struct SearchView: View {
    @State var searchText: String = ""
    
    var body: some View {
        NavigationStack {
            VStack {
                Text("Search View")
            }
        }
        .searchable(text: $searchText)
    }
}
