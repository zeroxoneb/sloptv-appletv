import SwiftUI

/// Full grid for one category, with the site's filter chips across the top.
struct BrowseView: View {
    private static let chips: [(String, String)] = [
        ("all", "All"), ("music", "Music Videos"), ("episodes", "Episodes"),
        ("originals", "Originals"), ("restyles", "Restyles"), ("drips", "Drips"),
        ("sloptoberfest", "Sloptoberfest"),
    ]

    @State private var chip = "all"
    @State private var newest = true
    @State private var shelf = ShelfModel(ShelfSpec(title: "New", source: .fresh, chip: "all"))

    private let columns = Array(repeating: GridItem(.fixed(Theme.cardSize.width), spacing: 48), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 30) {
                    controls
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 60) {
                        ForEach(shelf.videos) { video in
                            PosterCard(video: video).onAppear { shelf.onAppear(video) }
                        }
                    }
                    .focusSection()
                    if shelf.isLoading { ProgressView().frame(maxWidth: .infinity) }
                    if shelf.loadedOnce && shelf.videos.isEmpty {
                        Text(shelf.error ?? "Nothing here yet.")
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 40)
            }
            .background(Theme.background)
            .navigationDestination(for: Video.self) { DetailView(video: $0) }
            .task(id: "\(chip):\(newest)") {
                shelf = ShelfModel(ShelfSpec(title: "", source: newest ? .fresh : .discover, chip: chip))
                await shelf.loadIfNeeded()
            }
        }
    }

    private var controls: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 20) {
                Button { newest.toggle() } label: {
                    Label(newest ? "Newest" : "Discover",
                          systemImage: newest ? "clock" : "sparkles")
                }
                Divider().frame(height: 50)
                ForEach(Self.chips, id: \.0) { value, label in
                    Button { chip = value } label: {
                        Text(label).fontWeight(chip == value ? .bold : .regular)
                    }
                    .tint(chip == value ? Theme.accent : nil)
                }
            }
            .padding(.vertical, 20)
        }
        .scrollClipDisabled()
        .focusSection()
    }
}
