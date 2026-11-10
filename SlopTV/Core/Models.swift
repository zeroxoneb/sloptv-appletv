import Foundation

struct Creator: Codable, Hashable {
    let handle: String
    let name: String?
    let avatarUrl: String?

    var displayName: String { (name?.isEmpty == false ? name : nil) ?? handle }
}

struct Video: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let creator: Creator
    let posterUrl: String?
    let previewUrl: String?
    let tier: String?
    let dur: String?
    let views: Int?
    let likes: Int?
    let days: Int?

    init(id: String, title: String, creator: Creator, posterUrl: String?, previewUrl: String? = nil,
         tier: String? = nil, dur: String? = nil, views: Int? = nil, likes: Int? = nil, days: Int? = nil) {
        self.id = id; self.title = title; self.creator = creator; self.posterUrl = posterUrl
        self.previewUrl = previewUrl; self.tier = tier; self.dur = dur; self.views = views
        self.likes = likes; self.days = days
    }

    var tierLabel: String? {
        switch tier {
        case "cannon_verified": return "Cannon Verified"
        case "cannon_scenes": return "Cannon Scenes"
        case "uploaded": return "Upload"
        default: return nil
        }
    }

    var ageLabel: String? {
        guard let days else { return nil }
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        case 2..<14: return "\(days) days ago"
        case 14..<60: return "\(days / 7) weeks ago"
        default: return "\(days / 30) months ago"
        }
    }

    func poster(width: Int) -> URL? { SlopAPI.imageURL(posterUrl, width: width) }
}

struct FeedPage: Decodable {
    let videos: [Video]
    let next: String?
}

struct LiveSlot: Decodable, Identifiable, Hashable {
    let slotId: String
    let videoId: String
    let title: String
    let creator: Creator
    let startsAt: Double
    let endsAt: Double
    let durationMs: Double
    let posterUrl: String?
    let thumbUrl: String?

    var id: String { slotId }

    var asVideo: Video {
        Video(id: videoId, title: title, creator: creator, posterUrl: posterUrl,
              dur: Self.format(seconds: durationMs / 1000))
    }

    static func format(seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct LiveNow: Decodable {
    let serverNow: Double
    let now: LiveSlot?
    let next: [LiveSlot]?
}

struct PlayInfo: Decodable {
    let manifestUrl: String
    let hlsUrl: String?
    let mp4Url: String?
    let ticket: String?
    let expiresAt: Double?
}

/// A horizontal row on the home screen, backed by one of the public browse feeds.
struct ShelfSpec: Hashable, Identifiable {
    enum Source: String { case discover, fresh }
    let title: String
    let source: Source
    let chip: String
    var id: String { "\(source.rawValue):\(chip)" }

    static let home: [ShelfSpec] = [
        .init(title: "Fresh off the Cannon", source: .fresh, chip: "all"),
        .init(title: "Discover", source: .discover, chip: "all"),
        .init(title: "Music Videos", source: .discover, chip: "music"),
        .init(title: "Episodes", source: .discover, chip: "episodes"),
        .init(title: "Originals", source: .discover, chip: "originals"),
        .init(title: "Restyles", source: .discover, chip: "restyles"),
        .init(title: "Drips", source: .discover, chip: "drips"),
        .init(title: "Sloptoberfest", source: .discover, chip: "sloptoberfest"),
    ]
}
