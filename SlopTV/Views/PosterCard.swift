import SwiftUI

/// A focusable 16:9 poster with the title and creator underneath.
struct PosterCard: View {
    let video: Video
    var size: CGSize = Theme.cardSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: video) {
                PosterImage(url: video.poster(width: 640), title: video.title)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        if let dur = video.dur { Badge(text: dur).padding(10) }
                    }
            }
            .buttonStyle(.card)

            VStack(alignment: .leading, spacing: 2) {
                Text(video.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(video.creator.displayName)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            .lineLimit(1)
            .frame(width: size.width, alignment: .leading)
        }
    }
}

/// A titled, horizontally scrolling, lazily paginated row.
struct ShelfRow: View {
    let shelf: ShelfModel

    var body: some View {
        if shelf.loadedOnce && shelf.videos.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(shelf.spec.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 80)

                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 40) {
                        if shelf.videos.isEmpty {
                            ForEach(0..<5, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Theme.surface)
                                    .frame(width: Theme.cardSize.width, height: Theme.cardSize.height)
                            }
                        }
                        ForEach(shelf.videos) { video in
                            PosterCard(video: video)
                                .onAppear { shelf.onAppear(video) }
                        }
                        if shelf.isLoading && !shelf.videos.isEmpty {
                            ProgressView().frame(height: Theme.cardSize.height)
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 30)
                }
                .scrollClipDisabled()
            }
            .focusSection()
            .task { await shelf.loadIfNeeded() }
        }
    }
}
