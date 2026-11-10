import SwiftUI

/// Colors from the site's "slop" dark palette.
enum Theme {
    static let background = Color(hex: 0x0B0B0A)
    static let surface = Color(hex: 0x151513)
    static let raised = Color(hex: 0x1D1D1A)
    static let line = Color(hex: 0x2B2A27)
    static let text = Color(hex: 0xEFEDE6)
    static let muted = Color(hex: 0xA09E95)
    static let accent = Color(hex: 0xFF6A4D)

    static let cardSize = CGSize(width: 384, height: 216)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Poster image with a dark placeholder that shows the title while loading or on failure.
struct PosterImage: View {
    let url: URL?
    var title: String = ""

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case let .success(image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                ZStack {
                    LinearGradient(colors: [Theme.raised, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
        }
    }
}

struct Badge: View {
    let text: String
    var color: Color = .black.opacity(0.7)
    var foreground: Color = Theme.text

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color, in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(foreground)
    }
}

struct LiveBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(.white).frame(width: 10, height: 10)
            Text("LIVE").font(.caption.weight(.heavy))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Theme.accent, in: Capsule())
        .foregroundStyle(.white)
    }
}
