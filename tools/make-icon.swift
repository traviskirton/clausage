// Usage: swift tools/make-icon.swift  → writes the AppIcon asset catalog
import AppKit

let svg = NSImage(contentsOf: URL(fileURLWithPath: "Resources/claude.svg"))!

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = NSRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.05, dy: s * 0.05)
    NSColor(red: 0.851, green: 0.467, blue: 0.341, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.2237, yRadius: rect.width * 0.2237).fill()

    // white glyph: draw SVG, then tint with sourceIn
    let g = rect.width * 0.58
    let glyphRect = NSRect(x: (s - g) / 2, y: (s - g) / 2, width: g, height: g)
    let glyph = NSImage(size: glyphRect.size, flipped: false) { r in
        svg.draw(in: r)
        NSColor.white.setFill()
        r.fill(using: .sourceIn)
        return true
    }
    glyph.draw(in: glyphRect)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// Writes Resources/Assets.xcassets/AppIcon.appiconset
let dir = "Resources/Assets.xcassets/AppIcon.appiconset"
try? FileManager.default.removeItem(atPath: dir)
try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)@\(scale)x.png"
        try! render(base * scale).write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
        images.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: URL(fileURLWithPath: "\(dir)/Contents.json"))
try! JSONSerialization.data(withJSONObject: ["info": ["version": 1, "author": "xcode"]])
    .write(to: URL(fileURLWithPath: "Resources/Assets.xcassets/Contents.json"))
print("wrote \(dir)")
