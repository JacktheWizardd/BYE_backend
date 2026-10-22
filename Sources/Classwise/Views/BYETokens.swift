// Generated from packages/tokens/tokens.json by scripts/build-tokens.mjs. Do not edit; edit tokens.json and rebuild.
// Copied into Sources/Classwise/Views/ by scripts/sync-bye-shared.mjs in the app repository.
import SwiftUI

/// Brand colors (light mode only).
enum BYEColor {
    static let paper = Color(byeHex: 0xFAF8F3) // ivory page
    static let linen = Color(byeHex: 0xF2EEE6) // panels, sidebars
    static let card = Color(byeHex: 0xFFFFFF)
    static let tile = Color(byeHex: 0xEAE5DB) // stone cards, bar tracks
    static let tileLine = Color(byeHex: 0xDDD6C9)
    static let ink = Color(byeHex: 0x161618) // Jet Black: text, primary buttons, sticker outlines
    static let ink2 = Color(byeHex: 0x5F5A52) // body text, 6.6:1 on paper
    static let ink3 = Color(byeHex: 0x6B665E) // fine print, 5.4:1 on paper
    static let line = Color(byeHex: 0xE2DCD0)
    static let lineStrong = Color(byeHex: 0x8C857A)
    static let accent = Color(byeHex: 0xF2C14E) // yellow: swipe, one headline phrase, rating bars, progress, and playful accents (confetti, avatar initials, primary button offset shadow). Never large surfaces, body text or backgrounds.
    static let brandSoft = Color(byeHex: 0xEFE9DD) // tag background
    static let signal = Color(byeHex: 0xB8401A) // warnings and errors only
}

/// Type sizes in points. Mac body text uses SF Pro; headings and numbers use Libre Baskerville.
enum BYESize {
    static let hero: CGFloat = 48
    static let title: CGFloat = 32
    static let heading: CGFloat = 24
    static let subheading: CGFloat = 20
    static let body: CGFloat = 16
    static let label: CGFloat = 14
    static let small: CGFloat = 13
    static let caption: CGFloat = 11
}

/// Spacing scale in points.
enum BYESpace {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Corner radii in points.
enum BYERadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 16
    static let card: CGFloat = 18
    static let window: CGFloat = 22
    static let pill: CGFloat = 999
}

/// Border widths in points.
enum BYEBorder {
    static let sticker: CGFloat = 1.5
    static let control: CGFloat = 1.5
    static let hairline: CGFloat = 1
}

/// Playful tilts in degrees.
enum BYETilt {
    static let note: Double = 0.6
    static let sticker: Double = 4
    static let idCard: Double = 4
}

/// Motion durations in seconds.
enum BYEDuration {
    static let fast: Double = 0.15
    static let slide: Double = 0.45
    static let screen: Double = 0.55
    static let swipe: Double = 0.9
    static let bars: Double = 1
    static let countUp: Double = 0.8
    static let stagger: Double = 0.07
    static let confetti: Double = 1.3
    static let typedHintTick: Double = 0.11
}

/// A cubic Bézier timing curve shared with the CSS `--bye-ease-*` variables.
struct BYECurve {
    let x1: Double, y1: Double, x2: Double, y2: Double
    func animation(_ duration: Double) -> Animation { .timingCurve(x1, y1, x2, y2, duration: duration) }
}

/// Easing curves.
enum BYEEasing {
    static let expo = BYECurve(x1: 0.16, y1: 1, x2: 0.3, y2: 1)
    static let spring = BYECurve(x1: 0.34, y1: 1.56, x2: 0.64, y2: 1)
}

/// The shared spring, used for toggles, selection and re-ordering.
enum BYESpring {
    static let response: Double = 0.45
    static let dampingFraction: Double = 0.7
    static var animation: Animation { .spring(response: response, dampingFraction: dampingFraction) }
}

/// One shadow layer. SwiftUI has no spread, so CSS spread values are not represented; `radius` is half the CSS blur.
struct BYEShadowLayer {
    let color: Color, radius: CGFloat, x: CGFloat, y: CGFloat
}

/// Shadows, as layers to apply in order.
enum BYEShadow {
    static let float: [BYEShadowLayer] = [BYEShadowLayer(color: BYEColor.ink.opacity(0.05), radius: 0, x: 0, y: 1), BYEShadowLayer(color: BYEColor.ink.opacity(0.38), radius: 24, x: 0, y: 24)]
    static let soft: [BYEShadowLayer] = [BYEShadowLayer(color: BYEColor.ink.opacity(0.04), radius: 0, x: 0, y: 1), BYEShadowLayer(color: BYEColor.ink.opacity(0.3), radius: 14, x: 0, y: 12)]
    static let sticker: [BYEShadowLayer] = [BYEShadowLayer(color: BYEColor.ink.opacity(1), radius: 0, x: 2, y: 2)]
    static let stickerLarge: [BYEShadowLayer] = [BYEShadowLayer(color: BYEColor.ink.opacity(1), radius: 0, x: 4, y: 4)]
    static let accentOffset: [BYEShadowLayer] = [BYEShadowLayer(color: BYEColor.accent.opacity(1), radius: 0, x: 3, y: 3)]
}

extension Color {
    /// Creates a color from a 0xRRGGBB value.
    init(byeHex value: UInt32) {
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
