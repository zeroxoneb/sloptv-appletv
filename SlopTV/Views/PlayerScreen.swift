import AVKit
import SwiftUI

/// Full-screen on-demand playback for one video.
struct PlayerScreen: View {
    let video: Video
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var error: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                SystemPlayer(player: player)
                    .ignoresSafeArea()
            } else if let error {
                PlaybackError(message: error, retry: { Task { await load() } }, close: { dismiss() })
            } else {
                ProgressView("Loading \(video.title)…")
            }
        }
        .task { await load() }
        .onDisappear { player?.pause() }
    }

    private func load() async {
        error = nil
        do {
            let url = try await SlopAPI.shared.playbackURL(for: video.id)
            let item = await PlayerItemFactory.make(url: url, video: video)
            let p = AVPlayer(playerItem: item)
            player = p
            p.play()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct PlaybackError: View {
    let message: String
    let retry: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Theme.accent)
            Text("Couldn’t play this video").font(.title2.bold())
            Text(message).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: 1000)
            HStack(spacing: 40) {
                Button("Try Again", action: retry)
                Button("Close", action: close)
            }
        }
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

/// Wraps AVPlayerViewController so we get the native tvOS transport bar, scrubbing and info panel.
struct SystemPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    var linear = false

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.requiresLinearPlayback = linear
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
        vc.requiresLinearPlayback = linear
    }

    static func dismantleUIViewController(_ vc: AVPlayerViewController, coordinator: ()) {
        vc.player?.pause()
    }
}
