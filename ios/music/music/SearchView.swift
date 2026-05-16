import SwiftUI

struct SearchView: View {
    @State var searchText: String = ""

    var body: some View {
        NavigationStack {
            SearchResultsView(query: searchText)
        }
        .searchable(text: $searchText, prompt: "Search songs")
    }
}
