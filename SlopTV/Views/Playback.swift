import AVKit
import SwiftUI

/// Full-screen playback, presented the standard tvOS way: Apple's AVPlayerViewController shown
/// modally on top of the app. The remote's Back/Menu button hides the controls, and a second
/// press closes the player and returns to whatever screen you were on.
///
/// Everything extra (the 👍 in the control bar, the toast, the live banner, loading and errors)
/// hangs off the player view controller rather than wrapping it.
@MainActor @Observable
final class Playback: NSObject, @preconcurrency AVPlayerViewControllerDelegate {
    enum Mode {
        case film(Video)
        case live(LiveChannelPlayer)
    }

    /// Plays one film.
    static func play(_ video: Video) { start(Playback(mode: .film(video))) }

    /// Plays the live channel, following the broadcast schedule.
    static func playLive() { start(Playback(mode: .live(LiveChannelPlayer()))) }

    /// The playback on screen, kept alive until the player is closed.
    private static var current: Playback?

    private static func start(_ playback: Playback) {
        guard current == nil, let presenter = topViewController() else { return }
        current = playback
        playback.present(from: presenter)
    }

    let mode: Mode
    let toast = ToastModel()
    private(set) var isLoading = true
    private(set) var bannerSlot: LiveSlot?

    @ObservationIgnored private let controller = AVPlayerViewController()
    @ObservationIgnored private var overlay: UIHostingController<PlaybackOverlay>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    @ObservationIgnored private var finished = false

    private init(mode: Mode) {
        self.mode = mode
        super.init()
    }

    /// The film on screen right now (changes from slot to slot on the live channel).
    var videoID: String? {
        switch mode {
        case let .film(video): video.id
        case let .live(channel): channel.slot?.videoId
        }
    }

    // MARK: Presenting and closing

    private func present(from presenter: UIViewController) {
        controller.delegate = self
        controller.modalPresentationStyle = .fullScreen
        controller.loadViewIfNeeded()
        if case let .live(channel) = mode {
            controller.player = channel.player
            controller.requiresLinearPlayback = true // it's a broadcast: no seeking
        }
        installOverlay()
        updateLikeButton()
        presenter.present(controller, animated: true)
        loadTask = Task { await load() }
    }

    /// Closes the player from code (the remote's Back button closes it on its own).
    private func close() {
        controller.dismiss(animated: true) { [weak self] in self?.finish() }
    }

    func playerViewControllerDidEndDismissalTransition(_ playerViewController: AVPlayerViewController) {
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        loadTask?.cancel()
        bannerTask?.cancel()
        controller.player?.pause()
        if case let .live(channel) = mode { channel.stop() }
        if Self.current === self { Self.current = nil }
    }

    // MARK: Loading

    private func load() async {
        isLoading = true
        switch mode {
        case let .film(video):
            do {
                let url = try await SlopAPI.shared.playbackURL(for: video.id)
                let item = await PlayerItemFactory.make(url: url, video: video)
                guard !Task.isCancelled else { return }
                let player = AVPlayer(playerItem: item)
                controller.player = player
                player.play()
                isLoading = false
                await refreshRating()
            } catch {
                isLoading = false
                showError(error.localizedDescription)
            }

        case let .live(channel):
            await channel.start()
            isLoading = false
            // Follow the channel: refresh the banner and 👍 whenever a new film starts.
            var shownSlot: String?
            while !Task.isCancelled {
                if let error = channel.error {
                    showError(error)
                    return
                }
                if let slot = channel.slot, slot.slotId != shownSlot {
                    shownSlot = slot.slotId
                    showBanner(slot)
                    await refreshRating()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Couldn’t play this video", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Try Again", style: .default) { [weak self] _ in
            guard let self else { return }
            loadTask = Task { await self.load() }
        })
        alert.addAction(UIAlertAction(title: "Close", style: .cancel) { [weak self] _ in self?.close() })
        controller.present(alert, animated: true)
    }

    private func showBanner(_ slot: LiveSlot) {
        bannerSlot = slot
        bannerTask?.cancel()
        bannerTask = Task {
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { bannerSlot = nil }
        }
    }

    // MARK: 👍

    /// Shows the 👍 for the film on screen, filled in if you've already liked it.
    private func refreshRating() async {
        updateLikeButton() // always show it; signed out, it explains how to sign in
        guard AccountModel.shared.isSignedIn, let id = videoID else { return }
        await RatingStore.shared.refresh(id)
        updateLikeButton()
    }

    /// Puts a 👍 button at the right of the player's control bar (swipe down to show it).
    private func updateLikeButton() {
        guard let id = videoID else {
            controller.transportBarCustomMenuItems = []
            return
        }
        let liked = RatingStore.shared.isLiked(id)
        let action = UIAction(
            title: liked ? "Liked" : "Like",
            image: UIImage(systemName: liked ? "hand.thumbsup.fill" : "hand.thumbsup"),
            state: liked ? .on : .off
        ) { [weak self] _ in
            Task { await self?.toggleLike(id) }
        }
        controller.transportBarCustomMenuItems = [action]
    }

    private func toggleLike(_ id: String) async {
        let message = await RatingStore.shared.toggleLike(id)
        toast.show(message)
        updateLikeButton()
    }

    // MARK: Overlay

    /// SwiftUI layer between the video and the player's controls, for the toast and banner.
    private func installOverlay() {
        guard let container = controller.contentOverlayView else { return }
        let host = UIHostingController(rootView: PlaybackOverlay(playback: self))
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        host.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: container.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        overlay = host
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}

struct PlaybackOverlay: View {
    let playback: Playback

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if playback.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let slot = playback.bannerSlot {
                HStack(spacing: 20) {
                    LiveBadge()
                    VStack(alignment: .leading) {
                        Text(slot.title).font(.headline)
                        Text(slot.creator.displayName).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(60)
                .transition(.opacity)
            }
        }
        .toast(playback.toast)
        .animation(.easeInOut(duration: 0.3), value: playback.bannerSlot?.slotId)
    }
}

@MainActor
enum PlayerItemFactory {
    /// Builds an item that carries the site's cookies (for signed segment URLs) and
    /// title/artwork metadata for the tvOS info panel.
    static func make(url: URL, video: Video) async -> AVPlayerItem {
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetHTTPCookiesKey: SlopAPI.shared.cookies,
            AVURLAssetHTTPUserAgentKey: SlopAPI.browserUserAgent,
            "AVURLAssetHTTPHeaderFieldsKey": SlopAPI.mediaHeaders,
        ])
        let item = AVPlayerItem(asset: asset)
        var metadata = [
            metadataItem(.commonIdentifierTitle, video.title),
            metadataItem(.iTunesMetadataTrackSubTitle, "by \(video.creator.displayName)"),
        ]
        if let artURL = video.poster(width: 640),
           let (data, _) = try? await SlopAPI.shared.session.data(from: artURL),
           let image = UIImage(data: data), let png = image.pngData() {
            metadata.append(metadataItem(.commonIdentifierArtwork, png as NSData, dataType: kCMMetadataBaseDataType_PNG as String))
        }
        item.externalMetadata = metadata
        return item
    }

    private static func metadataItem(_ id: AVMetadataIdentifier, _ value: NSCopying & NSObjectProtocol,
                                     dataType: String? = nil) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = id
        item.value = value
        item.extendedLanguageTag = "und"
        if let dataType { item.dataType = dataType }
        return item.copy() as! AVMetadataItem
    }

    private static func metadataItem(_ id: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
        metadataItem(id, value as NSString)
    }
}
