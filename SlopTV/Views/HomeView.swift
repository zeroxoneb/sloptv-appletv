import SwiftUI

struct HomeView: View {
    @State private var model = HomeModel()
    @State private var playing: Video?
    @State private var watchingLive = false

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 30) {
                    HeroView(video: model.hero,
                             isLive: model.live?.now != nil,
                             onPlay: { video in
                                 if model.live?.now?.videoId == video.id { watchingLive = true } else { playing = video }
                             })
                    ForEach(model.shelves) { shelf in
                        ShelfRow(shelf: shelf)
                    }
                }
                .padding(.bottom, 80)
            }
            .ignoresSafeArea(edges: [.top, .horizontal])
            .background(Theme.background)
            .navigationDestination(for: Video.self) { DetailView(video: $0) }
            .task {
                #if DEBUG
                // `-autoplayLive` launch argument: jump straight into the channel (used for testing).
                if ProcessInfo.processInfo.arguments.contains("-autoplayLive") { watchingLive = true }
                #endif
                await model.load()
            }
            .refreshable { await model.load() }
        }
        .fullScreenCover(item: $playing) { PlayerScreen(video: $0) }
        .fullScreenCover(isPresented: $watchingLive) { LivePlayerScreen() }
    }
}

/// Netflix-style billboard at the top of Home.
struct HeroView: View {
    let video: Video?
    let isLive: Bool
    let onPlay: (Video) -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PosterImage(url: video?.poster(width: 1920))
                .frame(maxWidth: .infinity)
                .frame(height: 760)
                .clipped()
                .overlay {
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0.35),
                        .init(color: Theme.background.opacity(0.85), location: 0.8),
                        .init(color: Theme.background, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
                .overlay {
                    LinearGradient(colors: [Theme.background.opacity(0.8), .clear],
                                   startPoint: .leading, endPoint: .center)
                }

            if let video {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 16) {
                        Text("SLOP TV")
                            .font(.headline.weight(.black))
                            .foregroundStyle(Theme.accent)
                        if isLive { LiveBadge() }
                    }
                    Text(video.title)
                        .font(.system(size: 76, weight: .heavy))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .frame(maxWidth: 1100, alignment: .leading)
                    Text("by \(video.creator.displayName)")
                        .font(.title3)
                        .foregroundStyle(Theme.muted)

                    HStack(spacing: 30) {
                        Button { onPlay(video) } label: {
                            Label(isLive ? "Watch Live" : "Play", systemImage: "play.fill")
                                .padding(.horizontal, 20)
                        }
                        NavigationLink(value: video) {
                            Label("More Info", systemImage: "info.circle")
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal, 80)
                .padding(.bottom, 40)
            }
        }
        .focusSection()
    }
}
