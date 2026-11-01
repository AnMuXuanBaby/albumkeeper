import SwiftUI

@main
struct AlbumKeeperApp: App {
    @StateObject private var library = PhotoLibraryService()
    @StateObject private var selection = SelectionStore()
    @StateObject private var tags = TagStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(selection)
                .environmentObject(tags)
        }
    }
}
