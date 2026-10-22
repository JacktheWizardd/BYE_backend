import SwiftUI
import ClasswiseCore

/// A BYE review's collectible postage stamp, drawn like the shared `ByeStamp` (packages/ui): a perforated 40×50 frame,
/// a panel and "BYE". The tier only changes the look and comes from the review ID (`StampTier`), never its scores.
struct ByeStamp: View {
    let tier: StampTier
    /// Drawn width in points; 32 on review cards, 24 in score rows. Height follows the 4:5 stamp.
    var width: CGFloat = 32

    private static let size = CGSize(width: 40, height: 50)

    var body: some View {
        Canvas { context, canvas in
            context.scaleBy(x: canvas.width / Self.size.width, y: canvas.height / Self.size.height)
            let look = Look(tier)
            // Frame, with perforation holes punched out of every edge.
            context.drawLayer { frame in
                frame.fill(Path(CGRect(origin: .zero, size: Self.size)), with: .color(look.frame))
                if tier == .uncommon {
                    frame.stroke(Path(CGRect(x: 0.6, y: 0.6, width: 38.8, height: 48.8)), with: .color(Palette.ink), lineWidth: 1.2)
                }
                frame.blendMode = .destinationOut
                for hole in Self.holes { frame.fill(Path(ellipseIn: CGRect(x: hole.x - 1.8, y: hole.y - 1.8, width: 3.6, height: 3.6)), with: .color(.black)) }
            }
            let panel = Path(roundedRect: CGRect(x: 4.5, y: 4.5, width: 31, height: 41), cornerRadius: 1)
            context.fill(panel, with: .color(look.panel))
            if tier == .uncommon { context.stroke(panel, with: .color(Palette.ink), lineWidth: 0.8) }
            if tier == .legendary {
                context.stroke(Path(roundedRect: CGRect(x: 6.3, y: 6.3, width: 27.4, height: 37.4), cornerRadius: 0.6), with: .color(Palette.ink), lineWidth: 0.6)
            }
            if tier == .uncommon {
                context.fill(Path(roundedRect: CGRect(x: 7, y: 27.5, width: 26, height: 4), cornerRadius: 1.5), with: .color(Palette.highlight))
            }
            // "BYE" stretched to 23 units wide, baseline at 29.5, like SVG textLength.
            let word = context.resolve(Text("BYE").font(BYEFont.display(11, bold: true)).foregroundStyle(look.word))
            let measured = word.measure(in: CGSize(width: 100, height: 100))
            var text = context
            text.translateBy(x: 20, y: 29.5)
            text.scaleBy(x: measured.width > 0 ? 23 / measured.width : 1, y: 1)
            text.draw(word, at: .zero, anchor: .bottom)
            if tier == .epic || tier == .legendary {
                var postmark = Path(ellipseIn: CGRect(x: 24, y: 31, width: 14, height: 14))
                for y in [35.0, 39, 43] {
                    postmark.move(to: CGPoint(x: 19, y: y))
                    for step in 0..<4 {
                        let x = 19 + Double(step) * 6
                        postmark.addQuadCurve(to: CGPoint(x: x + 6, y: y), control: CGPoint(x: x + 3, y: step.isMultiple(of: 2) ? y - 2 : y + 2))
                    }
                }
                context.stroke(postmark, with: .color(Palette.signal.opacity(0.85)), lineWidth: 0.9)
            }
        }
        .frame(width: width, height: width * 1.25)
        .shadow(color: Palette.lineStrong, radius: 0.6)
        .rotationEffect(.degrees(-BYETilt.sticker))
        .accessibilityElement()
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel("From BYE students · \(tier.rawValue) stamp")
        .help("From BYE students · \(tier.rawValue) stamp")
    }

    private static let holes: [CGPoint] = {
        var points: [CGPoint] = []
        for x in stride(from: 2.5, to: 40, by: 5) { points += [CGPoint(x: x, y: 0), CGPoint(x: x, y: 50)] }
        for y in stride(from: 2.5, to: 50, by: 5) { points += [CGPoint(x: 0, y: y), CGPoint(x: 40, y: y)] }
        return points
    }()

    private struct Look {
        let frame: Color, panel: Color, word: Color
        init(_ tier: StampTier) {
            switch tier {
            case .common, .epic: (frame, panel, word) = (Palette.tile, Palette.ink, Palette.paper2)
            case .uncommon: (frame, panel, word) = (Palette.paper, Palette.paper, Palette.ink)
            case .rare: (frame, panel, word) = (Palette.tile, Palette.highlight, Palette.ink)
            case .legendary: (frame, panel, word) = (Palette.ink, Palette.highlight, Palette.ink)
            }
        }
    }
}
