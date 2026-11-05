import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let iconSet = root
    .appendingPathComponent("VidgetYo/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

let outputs: [(filename: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func iconFont(size: CGFloat) -> NSFont {
    let candidates = [
        ".AppleSystemUIFontRounded-Bold",
        "SFProRounded-Bold",
        "HelveticaNeue-Bold",
        "Arial-BoldMT",
    ]
    for name in candidates {
        if let font = NSFont(name: name, size: size) {
            return font
        }
    }
    return NSFont.systemFont(ofSize: size, weight: .bold)
}

func drawIcon(pixels: Int) -> NSBitmapImageRep? {
    let size = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return nil
    }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = context

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let corner = size * 0.2237
    let clip = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    clip.addClip()

    let top = NSColor(calibratedRed: 0.16, green: 0.48, blue: 0.34, alpha: 1)
    let bottom = NSColor(calibratedRed: 0.28, green: 0.68, blue: 0.46, alpha: 1)
    NSGradient(colors: [top, bottom])?.draw(in: rect, angle: 145)

    let highlight = NSBezierPath(ovalIn: NSRect(x: size * 0.08, y: size * 0.52, width: size * 0.84, height: size * 0.40))
    NSColor(white: 1, alpha: 0.08).setFill()
    highlight.fill()

    let fontSize = size * 0.56
    let font = iconFont(size: fontSize)
    let text = "Ё" as NSString
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .kern: -size * 0.02,
    ]
    let textSize = text.size(withAttributes: attributes)
    let textRect = NSRect(
        x: (size - textSize.width) / 2,
        y: (size - textSize.height) / 2 - size * 0.03,
        width: textSize.width,
        height: textSize.height
    )
    text.draw(in: textRect, withAttributes: attributes)

    context.flushGraphics()
    return rep
}

try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

for item in outputs {
    guard let rep = drawIcon(pixels: item.pixels),
          let data = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to render \(item.filename)\n", stderr)
        exit(1)
    }
    try data.write(to: iconSet.appendingPathComponent(item.filename))
}

print("Wrote AppIcon to \(iconSet.path)")
