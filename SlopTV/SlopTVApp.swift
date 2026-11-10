import SwiftUI

@main
struct SlopTVApp: App {
    enum Section: Hashable { case home, live, browse, account }

    @State private var section: Section = Self.launchArgument("-signIn") ? .account : .home

    init() {
        // Posters are re-requested a lot while scrolling rows; keep them around.
        URLCache.shared = URLCache(memoryCapacity: 96 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $section) {
                Tab("Home", systemImage: "house.fill", value: .home) { HomeView() }
                Tab("Live", systemImage: "dot.radiowaves.left.and.right", value: .live) { LiveView() }
                Tab("Browse", systemImage: "square.grid.2x2.fill", value: .browse) { BrowseView() }
                Tab("Account", systemImage: "person.crop.circle", value: .account) { AccountView() }
            }
            .task { await AccountModel.shared.restore() }
            .tint(Theme.accent)
            .preferredColorScheme(.dark)
            .background(Theme.background)
        }
    }

    /// Debug-only launch arguments used for testing in the simulator
    /// (`-autoplayLive`, `-signIn`). Always false in release builds.
    static func launchArgument(_ name: String) -> Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(name)
        #else
        false
        #endif
    }
}
