// Generates the tvOS app icon (layered image stacks) and top shelf images.
// Usage: swift scripts/make_icons.swift   (run from the repo root)
import AppKit
import CoreGraphics
import CoreText
import Foundation

let root = URL(fileURLWithPath: "SlopTV/Assets.xcassets")
let brand = root.appendingPathComponent("App Icon & Top Shelf Image.brandassets")
let info: [String: Any] = ["author": "xcode", "version": 1]

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func writeJSON(_ obj: Any, to dir: URL) {
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let data = try! JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: dir.appendingPathComponent("Contents.json"))
}

func png(width: Int, height: Int, opaque: Bool, to url: URL, draw: (CGContext, CGFloat, CGFloat) -> Void) {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx, CGFloat(width), CGFloat(height))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

func background(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    ctx.setFillColor(color(0x0B0B0A)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let glow = CGGradient(colorsSpace: nil, colors: [color(0xFF6A4D, 0.55), color(0xFF6A4D, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: w * 0.78, y: h * 0.15), startRadius: 0,
                           endCenter: CGPoint(x: w * 0.78, y: h * 0.15), endRadius: max(w, h) * 0.7, options: [])
    // CRT scanlines for a bit of TV texture.
    ctx.setFillColor(color(0x000000, 0.18))
    var y: CGFloat = 0
    while y < h { ctx.fill(CGRect(x: 0, y: y, width: w, height: max(1, h / 240))); y += max(2, h / 120) }
}

func wordmark(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat, scale: CGFloat, center: CGPoint) {
    func line(_ text: String, size: CGFloat, color c: CGColor, kern: CGFloat) -> CTLine {
        let font = CTFontCreateWithName("HelveticaNeue-CondensedBlack" as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: c, .kern: kern]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    }
    let slop = line("SLOP", size: h * 0.42 * scale, color: color(0xEFEDE6), kern: h * 0.01 * scale)
    let tv = line("TV", size: h * 0.42 * scale, color: color(0xFF6A4D), kern: 0)
    let gap = h * 0.04 * scale
    let w1 = CTLineGetTypographicBounds(slop, nil, nil, nil)
    let w2 = CTLineGetTypographicBounds(tv, nil, nil, nil)
    let total = CGFloat(w1 + w2) + gap
    let baseline = center.y - h * 0.14 * scale
    ctx.setShadow(offset: CGSize(width: 0, height: -h * 0.02), blur: h * 0.05, color: color(0, 0.6))
    ctx.textPosition = CGPoint(x: center.x - total / 2, y: baseline); CTLineDraw(slop, ctx)
    ctx.textPosition = CGPoint(x: center.x - total / 2 + CGFloat(w1) + gap, y: baseline); CTLineDraw(tv, ctx)
}

func imageset(_ dir: URL, base: String, sizes: [(Int, Int, String)], opaque: Bool,
              draw: @escaping (CGContext, CGFloat, CGFloat) -> Void) {
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var images: [[String: Any]] = []
    for (w, h, scale) in sizes {
        let name = scale == "1x" ? "\(base).png" : "\(base)@\(scale).png"
        png(width: w, height: h, opaque: opaque, to: dir.appendingPathComponent(name), draw: draw)
        images.append(["filename": name, "idiom": "tv", "scale": scale])
    }
    writeJSON(["images": images, "info": info], to: dir)
}

func imagestack(_ name: String, sizes: [(Int, Int, String)]) {
    let dir = brand.appendingPathComponent("\(name).imagestack")
    let layers: [(String, Bool, (CGContext, CGFloat, CGFloat) -> Void)] = [
        ("Front", false, { ctx, w, h in wordmark(ctx, w, h, scale: 0.8, center: CGPoint(x: w / 2, y: h / 2)) }),
        ("Back", true, background),
    ]
    for (layer, opaque, draw) in layers {
        let layerDir = dir.appendingPathComponent("\(layer).imagestacklayer")
        writeJSON(["info": info], to: layerDir)
        imageset(layerDir.appendingPathComponent("Content.imageset"), base: layer.lowercased(),
                 sizes: sizes, opaque: opaque, draw: draw)
    }
    writeJSON(["info": info, "layers": layers.map { ["filename": "\($0.0).imagestacklayer"] }], to: dir)
}

func topShelf(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    background(ctx, w, h)
    wordmark(ctx, w, h, scale: 0.9, center: CGPoint(x: w / 2, y: h / 2))
}

try? FileManager.default.removeItem(at: brand)
writeJSON(["info": info], to: root)
writeJSON(["colors": [["idiom": "universal", "color": ["color-space": "srgb", "components":
    ["red": "0xFF", "green": "0x6A", "blue": "0x4D", "alpha": "1.000"]]]], "info": info],
          to: root.appendingPathComponent("AccentColor.colorset"))

imagestack("App Icon", sizes: [(400, 240, "1x"), (800, 480, "2x")])
imagestack("App Icon - App Store", sizes: [(1280, 768, "1x")])
imageset(brand.appendingPathComponent("Top Shelf Image.imageset"), base: "topshelf",
         sizes: [(1920, 720, "1x"), (3840, 1440, "2x")], opaque: true, draw: topShelf)
imageset(brand.appendingPathComponent("Top Shelf Image Wide.imageset"), base: "topshelf-wide",
         sizes: [(2320, 720, "1x"), (4640, 1440, "2x")], opaque: true, draw: topShelf)

writeJSON(["assets": [
    ["filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
    ["filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
    ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"],
    ["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
], "info": info], to: brand)

print("Wrote icons to \(brand.path)")
