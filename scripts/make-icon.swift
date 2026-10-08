// Generates Wiska's app icon and menu-bar mark (Midnight Aurora).
// Usage: swift scripts/make-icon.swift Wiska/Assets.xcassets
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let teal = CGColor(srgbRed: 0x3E / 255, green: 0xE6 / 255, blue: 0xC1 / 255, alpha: 1)
let violet = CGColor(srgbRed: 0x8B / 255, green: 0x6C / 255, blue: 0xFF / 255, alpha: 1)
let bars: [CGFloat] = [10, 26, 42, 22, 8]          // heights in a 50-unit box

func png(_ size: Int, to url: URL, draw: (CGContext, CGFloat) -> Void) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx, CGFloat(size))
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

func drawBars(_ ctx: CGContext, in rect: CGRect, gradient: Bool, color: CGColor = .black) {
    let unit = rect.width / 50
    let width = 6 * unit, gap = (rect.width - 5 * width) / 6
    for (i, h) in bars.enumerated() {
        let height = h * unit
        let bar = CGRect(x: rect.minX + gap + CGFloat(i) * (width + gap), y: rect.midY - height / 2,
                         width: width, height: height)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: width / 2, cornerHeight: width / 2, transform: nil))
        ctx.clip()
        if gradient {
            let g = CGGradient(colorsSpace: nil, colors: [teal, violet] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: 0), end: CGPoint(x: rect.maxX, y: 0), options: [])
        } else {
            ctx.setFillColor(color)
            ctx.fill(bar)
        }
        ctx.restoreGState()
    }
}

func appIcon(_ ctx: CGContext, _ s: CGFloat) {
    let body = CGRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024)
    let path = CGPath(roundedRect: body, cornerWidth: body.width * 0.2237, cornerHeight: body.width * 0.2237, transform: nil)
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let bg = CGGradient(colorsSpace: nil, colors: [CGColor(srgbRed: 0x1E / 255, green: 0x26 / 255, blue: 0x33 / 255, alpha: 1),
                                                   CGColor(srgbRed: 0x0B / 255, green: 0x0E / 255, blue: 0x13 / 255, alpha: 1)] as CFArray,
                        locations: [0, 1])!
    ctx.drawRadialGradient(bg, startCenter: CGPoint(x: body.minX + body.width * 0.3, y: body.maxY - body.height * 0.2),
                           startRadius: 0, endCenter: CGPoint(x: body.midX, y: body.midY), endRadius: body.width * 0.75,
                           options: [.drawsAfterEndLocation])
    ctx.restoreGState()
    drawBars(ctx, in: body.insetBy(dx: body.width * 0.18, dy: body.height * 0.18), gradient: true)
}

// AppIcon.appiconset
let iconSet = out.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)@\(scale)x.png"
        png(points * scale, to: iconSet.appendingPathComponent(name), draw: appIcon)
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
try JSONSerialization.data(withJSONObject: ["images": images, "info": ["version": 1, "author": "xcode"]],
                           options: [.prettyPrinted]).write(to: iconSet.appendingPathComponent("Contents.json"))

// MenuBarIcon.imageset (template)
let menuSet = out.appendingPathComponent("MenuBarIcon.imageset")
try FileManager.default.createDirectory(at: menuSet, withIntermediateDirectories: true)
for scale in [1, 2] {
    png(18 * scale, to: menuSet.appendingPathComponent("menubar@\(scale)x.png")) { ctx, s in
        drawBars(ctx, in: CGRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.05, dy: s * 0.05), gradient: false)
    }
}
try JSONSerialization.data(withJSONObject: [
    "images": [["idiom": "universal", "scale": "1x", "filename": "menubar@1x.png"],
               ["idiom": "universal", "scale": "2x", "filename": "menubar@2x.png"]],
    "info": ["version": 1, "author": "xcode"],
    "properties": ["template-rendering-intent": "template"],
], options: [.prettyPrinted]).write(to: menuSet.appendingPathComponent("Contents.json"))

try JSONSerialization.data(withJSONObject: ["info": ["version": 1, "author": "xcode"]], options: [.prettyPrinted])
    .write(to: out.appendingPathComponent("Contents.json"))
print("wrote \(out.path)")
