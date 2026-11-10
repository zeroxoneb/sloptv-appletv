import SwiftUI

struct DetailView: View {
    let video: Video
    @State private var playing: Video?
    @State private var related = ShelfModel(ShelfSpec(title: "More Like This", source: .discover, chip: "all"))

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 40) {
                header
                ShelfRow(shelf: related)
            }
            .padding(.bottom, 80)
        }
        .ignoresSafeArea(edges: [.top, .horizontal])
        .background {
            ZStack {
                Theme.background
                PosterImage(url: video.poster(width: 1920))
                    .blur(radius: 40)
                    .opacity(0.35)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $playing) { PlayerScreen(video: $0) }
    }

    private var meta: [String] {
        var parts: [String] = []
        if let dur = video.dur { parts.append(dur) }
        if let views = video.views { parts.append("\(views) view\(views == 1 ? "" : "s")") }
        if let likes = video.likes { parts.append("\(likes) like\(likes == 1 ? "" : "s")") }
        if let age = video.ageLabel { parts.append(age) }
        return parts
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 60) {
            VStack(alignment: .leading, spacing: 22) {
                if let tier = video.tierLabel {
                    Badge(text: tier.uppercased(), color: Theme.accent.opacity(0.18), foreground: Theme.accent)
                }
                Text(video.title)
                    .font(.system(size: 64, weight: .heavy))
                    .foregroundStyle(Theme.text)
                    .lineLimit(3)

                HStack(spacing: 14) {
                    if let avatar = SlopAPI.absolute(video.creator.avatarUrl) {
                        AsyncImage(url: avatar) { $0.resizable() } placeholder: { Theme.raised }
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                    }
                    Text(video.creator.displayName).font(.headline)
                    Text("@\(video.creator.handle)").foregroundStyle(Theme.muted)
                }
                .foregroundStyle(Theme.text)

                Text(meta.joined(separator: "  ·  "))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(Theme.muted)

                Button { playing = video } label: {
                    Label("Play", systemImage: "play.fill").padding(.horizontal, 30)
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PosterImage(url: video.poster(width: 1920), title: video.title)
                .frame(width: 880, height: 495)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.6), radius: 30, y: 20)
        }
        .padding(.horizontal, 80)
        .padding(.top, 120)
        .focusSection()
    }
}
