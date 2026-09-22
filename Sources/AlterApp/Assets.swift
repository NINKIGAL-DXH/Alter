import SwiftUI
import ImageIO
import AlterCore

struct Expression: Decodable, Identifiable {
    let id: Int
    let name: String
    let state: String
    let quote: String
    let file: String
    /// Normalized top-left content rectangle, excluding captured game chrome.
    let crop: [Double]
}
enum Assets {
    // SwiftPM's native and Xcode build systems lay out resource bundles differently.
    // Prefer only resources physically inside the installed app before development fallbacks.
    static let root: URL = {
        let appBases = [Bundle.main.resourceURL, Bundle.main.bundleURL].compactMap { $0 }
        let suffixes = ["AlterAssets", "Alter_AlterApp.bundle/Contents/Resources/Resources", "Alter_AlterApp.bundle/Resources", "Alter_AlterApp.bundle/Contents/Resources"]
        for base in appBases {
            for suffix in suffixes {
                let candidate = base.appendingPathComponent(suffix)
                if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Expressions/expressions.json").path) { return candidate }
            }
        }
        let bundle = Bundle.module
        for candidate in [bundle.bundleURL.appendingPathComponent("Resources"), bundle.bundleURL.appendingPathComponent("Contents/Resources/Resources"), bundle.resourceURL?.appendingPathComponent("Resources")].compactMap({ $0 }) {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Expressions/expressions.json").path) { return candidate }
        }
        return Bundle.main.bundleURL.appendingPathComponent("MissingAlterResources")
    }()
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
        var rendered = cg
        if let expression = expressions.first(where: { relative == "Expressions/" + $0.file }), expression.crop.count == 4 {
            let c = expression.crop
            let bounds = CGRect(x: c[0] * Double(cg.width), y: c[1] * Double(cg.height), width: c[2] * Double(cg.width), height: c[3] * Double(cg.height))
            // Crop the bounded thumbnail; original reference files stay intact.
            let inner = CGRect(x: ceil(bounds.minX), y: ceil(bounds.minY), width: floor(bounds.maxX) - ceil(bounds.minX), height: floor(bounds.maxY) - ceil(bounds.minY))
            guard let cropped = cg.cropping(to: inner) else { return nil }
            rendered = cropped
        }
        let image = NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
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
            if prominent { content.buttonStyle(.glassProminent) }
            else { content.buttonStyle(.plain).padding(.horizontal, 13).padding(.vertical, 7).glassEffect(.clear.interactive(), in: .capsule) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.bordered) }
        }
    }
}
extension View {
    func glassAction(prominent: Bool = false) -> some View { modifier(GlassAction(prominent: prominent)) }
    func contentPanel() -> some View { padding(22).panelSurface() }
    func panelSurface(radius: CGFloat = 20) -> some View { modifier(PanelSurface(radius: radius)) }
}
struct PanelSurface: ViewModifier {
    var radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: radius))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.clear, in: .rect(cornerRadius: radius))
        } else {
            content.background(.ultraThinMaterial.opacity(0.45), in: RoundedRectangle(cornerRadius: radius))
                .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(0.24), lineWidth: 0.6) }
        }
    }
}

/// Native behind-window material lets desktop colors reach the clear glass controls.
/// AppKit automatically respects the system's Reduce Transparency preference.
struct WindowGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground; view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        DispatchQueue.main.async {
            view.window?.isOpaque = false
            view.window?.backgroundColor = .clear
        }
    }
}

struct AlterBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
            else {
                WindowGlass()
                LinearGradient(colors: [Color(red: 0.68, green: 0.63, blue: 0.83).opacity(0.13), .clear, Color(red: 0.82, green: 0.61, blue: 0.60).opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }.ignoresSafeArea()
    }
}
