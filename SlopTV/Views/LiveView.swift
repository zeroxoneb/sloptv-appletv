import AVKit
import SwiftUI

/// Keeps the server's live schedule and our clock offset from it.
@MainActor @Observable
final class LiveModel {
    private(set) var now: LiveSlot?
    private(set) var upcoming: [LiveSlot] = []
    private(set) var error: String?
    private var clockOffsetMs: Double = 0

    /// Current time on the server's clock, in ms since 1970.
    var serverNowMs: Double { Date().timeIntervalSince1970 * 1000 + clockOffsetMs }

    func refresh() async {
        do {
            let live = try await SlopAPI.shared.liveNow()
            clockOffsetMs = live.serverNow - Date().timeIntervalSince1970 * 1000
            now = live.now
            upcoming = live.next ?? []
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Refreshes the schedule whenever the current slot ends.
    func keepFresh() async {
        while !Task.isCancelled {
            await refresh()
            let wait = max(5, ((now?.endsAt ?? serverNowMs + 30_000) - serverNowMs) / 1000 + 1)
            try? await Task.sleep(for: .seconds(min(wait, 120)))
        }
    }
}

struct LiveView: View {
    @State private var model = LiveModel()

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 50) {
                    if let slot = model.now {
                        nowPlaying(slot)
                    } else if let error = model.error {
                        Text(error).foregroundStyle(Theme.muted).padding(80)
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(200)
                    }

                    if !model.upcoming.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Up Next on the Channel")
                                .font(.title3.bold())
                                .padding(.horizontal, 80)
                            ScrollView(.horizontal) {
                                LazyHStack(alignment: .top, spacing: 40) {
                                    ForEach(model.upcoming) { slot in
                                        VStack(alignment: .leading, spacing: 6) {
                                            PosterCard(video: slot.asVideo)
                                            Text(Date(timeIntervalSince1970: slot.startsAt / 1000), style: .time)
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(Theme.accent)
                                        }
                                    }
                                }
                                .padding(.horizontal, 80)
                                .padding(.vertical, 30)
                            }
                            .scrollClipDisabled()
                        }
                        .focusSection()
                    }
                }
                .padding(.bottom, 80)
            }
            .ignoresSafeArea(edges: [.top, .horizontal])
            .background(Theme.background)
            .navigationDestination(for: Video.self) { DetailView(video: $0) }
            .task { await model.keepFresh() }
        }
    }

    private func nowPlaying(_ slot: LiveSlot) -> some View {
        ZStack(alignment: .bottomLeading) {
            PosterImage(url: SlopAPI.imageURL(slot.posterUrl, width: 1920))
                .frame(maxWidth: .infinity)
                .frame(height: 760)
                .clipped()
                .overlay {
                    LinearGradient(colors: [.clear, Theme.background], startPoint: .center, endPoint: .bottom)
                }

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    LiveBadge()
                    Text("SLOP TV CHANNEL").font(.headline.weight(.black)).foregroundStyle(Theme.text)
                }
                Text(slot.title)
                    .font(.system(size: 72, weight: .heavy))
                    .lineLimit(2)
                Text("by \(slot.creator.displayName)")
                    .font(.title3)
                    .foregroundStyle(Theme.muted)

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let elapsed = (model.serverNowMs - slot.startsAt) / 1000
                    let total = slot.durationMs / 1000
                    HStack(spacing: 20) {
                        ProgressView(value: min(max(elapsed, 0), total), total: max(total, 1))
                            .tint(Theme.accent)
                            .frame(width: 600)
                        Text("\(LiveSlot.format(seconds: total - elapsed)) left")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(Theme.muted)
                    }
                }

                Button { Playback.playLive() } label: {
                    Label("Watch Live", systemImage: "play.fill").padding(.horizontal, 20)
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, 80)
        }
        .focusSection()
    }
}

/// Plays the live channel in sync with the server schedule, advancing slot to slot.
@MainActor @Observable
final class LiveChannelPlayer {
    let player = AVPlayer()
    private(set) var slot: LiveSlot?
    private(set) var error: String?
    private let schedule = LiveModel()
    private var endObserver: NSObjectProtocol?

    func start() async {
        error = nil
        await schedule.refresh()
        guard var current = schedule.now else {
            error = schedule.error ?? "Nothing is on air right now."
            return
        }
        // If the slot is nearly over, jump straight to the next one.
        if (current.endsAt - schedule.serverNowMs) < 3000, let next = schedule.upcoming.first {
            let wait = max(0, next.startsAt - schedule.serverNowMs) / 1000
            try? await Task.sleep(for: .seconds(wait))
            current = next
        }
        do {
            let url = try await SlopAPI.shared.playbackURL(for: current.videoId)
            let item = await PlayerItemFactory.make(url: url, video: current.asVideo)
            slot = current
            player.replaceCurrentItem(with: item)
            let offset = max(0, (schedule.serverNowMs - current.startsAt) / 1000)
            if offset > 1 {
                await player.seek(to: CMTime(seconds: offset, preferredTimescale: 600),
                                  toleranceBefore: .zero, toleranceAfter: .positiveInfinity)
            }
            player.play()
            observeEnd(of: item)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func observeEnd(of item: AVPlayerItem) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                await self?.start()
            }
        }
    }

    func stop() {
        player.pause()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }
}
