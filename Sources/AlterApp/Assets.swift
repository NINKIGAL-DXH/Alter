import SwiftUI
import ImageIO
import AlterCore

struct Expression: Decodable, Identifiable {
    let id: Int
    let name: String
    let state: String
    let quote: String
    let file: String
}
enum Assets {
    static var root: URL { Bundle.module.resourceURL!.appendingPathComponent("Resources") }
    static let expressions: [Expression] = {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("Expressions/expressions.json")), let result = try? JSONDecoder().decode([Expression].self, from: data) else { return [] }
        return result
    }()
    static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>(); c.totalCostLimit = 20 * 1024 * 1024; c.countLimit = 16; return c
    }()
    static func image(_ relative: String, pixels: Int = 900) -> NSImage? {
        let key = "\(relative):\(pixels)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let url = root.appendingPathComponent(relative)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: pixels, kCGImageSourceShouldCacheImmediately: true, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height)
        return image
    }
}
struct ExpressionImage: View {
    var number: Int
    var pixels = 900
    var fit: ContentMode = .fill
    var body: some View {
        if let ex = Assets.expressions.first(where: { $0.id == number }), let image = Assets.image("Expressions/" + ex.file, pixels: pixels) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: fit).accessibilityLabel(ex.name)
        } else { Color.gray.opacity(0.15) }
    }
}
struct BrandImage: View {
    var size: CGFloat = 40
    var body: some View {
        Group { if let image = Assets.image("Brand/Alter.png", pixels: 256) { Image(nsImage: image).resizable().scaledToFill() } }
            .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.24)).accessibilityLabel("Alter")
    }
}
struct GlassAction: ViewModifier {
    var prominent = false
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            if prominent { content.buttonStyle(.glassProminent) } else { content.buttonStyle(.glass) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.bordered) }
        }
    }
}
extension View {
    func glassAction(prominent: Bool = false) -> some View { modifier(GlassAction(prominent: prominent)) }
    func contentPanel() -> some View { padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20)) }
}
