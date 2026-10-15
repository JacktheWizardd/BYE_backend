// Renders the BYE wordmark app icon: Libre Baskerville Bold "BYE" over a highlighter swipe.
// Usage: swift scripts/render-wordmark-icon.swift Sources/Classwise/Resources/LibreBaskerville-Bold.ttf assets/branding/AppIcon.png
// Then run scripts/generate-app-icon.sh, which rounds and insets the square artwork.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let fontURL = URL(fileURLWithPath: args[1]) as CFURL
let output = URL(fileURLWithPath: args[2])
guard let descs = CTFontManagerCreateFontDescriptorsFromURL(fontURL) as? [CTFontDescriptor], let desc = descs.first else { fatalError("font") }

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

func render(name: String, bg: UInt32, ink: UInt32, swipe: UInt32, onSwipe: UInt32, rounded: Bool) {
    let size = 1024
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Full-bleed source, or the macOS tile (same geometry as scripts/render-app-icon.swift).
    let tile = rounded ? CGRect(x: 100, y: 100, width: 824, height: 824) : CGRect(x: 0, y: 0, width: 1024, height: 1024)
    if rounded {
        ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 184, cornerHeight: 184, transform: nil))
        ctx.clip()
    }
    ctx.setFillColor(rgb(bg))
    ctx.fill(tile)

    // Size the word to ~66% of the tile width.
    func line(_ pt: CGFloat, _ color: UInt32 = ink) -> (CTLine, CGFloat, CTFont) {
        let font = CTFontCreateWithFontDescriptor(desc, pt, nil)
        let attr = NSAttributedString(string: "BYE", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): rgb(color),
            NSAttributedString.Key(kCTKernAttributeName as String): pt * 0.01,
        ])
        let l = CTLineCreateWithAttributedString(attr)
        return (l, CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil)), font)
    }
    var (l, w, font) = line(100)
    let pt = 100 * (tile.width * 0.66) / w
    (l, w, font) = line(pt)
    let cap = CTFontGetCapHeight(font)
    let x = tile.midX - w / 2
    let baseline = tile.midY - cap / 2   // optically centre the capitals

    // Highlighter swipe: from just below the baseline up to ~38% of the cap height, overhanging both sides.
    let em = pt
    let bar = CGRect(x: x - em * 0.08, y: baseline - em * 0.1, width: w + em * 0.16, height: em * 0.3)
    ctx.setFillColor(rgb(swipe))
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: bar.height * 0.45, cornerHeight: bar.height * 0.45, transform: nil))
    ctx.fillPath()

    ctx.textPosition = CGPoint(x: x, y: baseline)
    CTLineDraw(l, ctx)
    // Where the letters cross the swipe they take the swipe's ink, like a real highlighter.
    if onSwipe != ink {
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: bar.height * 0.45, cornerHeight: bar.height * 0.45, transform: nil))
        ctx.clip()
        ctx.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line(pt, onSwipe).0, ctx)
        ctx.restoreGState()
    }

    let url = output
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("write \(name)") }
}

render(name: "AppIcon.png", bg: 0xFAF8F3, ink: 0x161618, swipe: 0xF2C14E, onSwipe: 0x161618, rounded: false)
