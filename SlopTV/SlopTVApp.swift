import SwiftUI

@main
struct SlopTVApp: App {
    init() {
        // Posters are re-requested a lot while scrolling rows; keep them around.
        URLCache.shared = URLCache(memoryCapacity: 96 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Home", systemImage: "house.fill") { HomeView() }
                Tab("Live", systemImage: "dot.radiowaves.left.and.right") { LiveView() }
                Tab("Browse", systemImage: "square.grid.2x2.fill") { BrowseView() }
            }
            .tint(Theme.accent)
            .preferredColorScheme(.dark)
            .background(Theme.background)
        }
    }
}
