import Foundation
import Observation

/// One paginated feed (a home row, or the "New" grid).
@MainActor @Observable
final class ShelfModel: Identifiable {
    let spec: ShelfSpec
    private(set) var videos: [Video] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var loadedOnce = false
    private var next: String?
    private let seed = String(UInt64.random(in: 0...UInt64.max), radix: 36)

    nonisolated var id: String { spec.id }

    init(_ spec: ShelfSpec) { self.spec = spec }

    var canLoadMore: Bool { !loadedOnce || next != nil }

    func loadIfNeeded() async {
        if !loadedOnce { await loadMore() }
    }

    func reload() async {
        videos = []; next = nil; loadedOnce = false; error = nil
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading, canLoadMore else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await SlopAPI.shared.feed(spec, after: next, seed: seed)
            let seen = Set(videos.map(\.id))
            videos += page.videos.filter { !seen.contains($0.id) }
            next = page.next
            loadedOnce = true
            error = nil
        } catch {
            self.error = error.localizedDescription
            loadedOnce = true
        }
    }

    /// Call from a cell's onAppear; prefetches when the user nears the end of the list.
    func onAppear(_ video: Video) {
        guard let index = videos.firstIndex(of: video), index >= videos.count - 6 else { return }
        Task { await loadMore() }
    }
}

@MainActor @Observable
final class HomeModel {
    let shelves = ShelfSpec.home.map(ShelfModel.init)
    private(set) var live: LiveNow?

    var hero: Video? {
        live?.now?.asVideo ?? shelves.first?.videos.first
    }

    func load() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadLive() }
            for shelf in shelves { group.addTask { await shelf.loadIfNeeded() } }
        }
    }

    func loadLive() async {
        live = try? await SlopAPI.shared.liveNow()
    }
}
