import SwiftUI

/// The v3 motion vocabulary, built from the shared tokens in BYETokens.swift. Every animation is
/// `nil` when Reduce Motion is on, so `withAnimation` and `.animation` change state instantly.
enum BYEMotion {
    /// Toggles and re-ordering: the shared spring (a little bounce).
    static func spring(reduce: Bool) -> Animation? { reduce ? nil : BYESpring.animation }
    /// Sidebar and professor highlights: a calm glide with no overshoot.
    static func glide(reduce: Bool) -> Animation? { reduce ? nil : BYEEasing.expo.animation(BYEDuration.slide) }
    /// Text and screen changes fade rather than slide.
    static func fade(reduce: Bool) -> Animation? { reduce ? nil : .easeOut(duration: BYEDuration.fast * 2) }
    /// Rating and seat bars grow to their new width.
    static func bars(reduce: Bool) -> Animation? { reduce ? nil : BYEEasing.expo.animation(BYEDuration.bars) }
    /// Numbers counting from the old value to the new one.
    static func count(reduce: Bool) -> Animation? { reduce ? nil : BYEEasing.expo.animation(BYEDuration.countUp) }
    /// The highlighter swipe under the wordmark and the greeting name.
    static func swipe(reduce: Bool) -> Animation? { reduce ? nil : BYEEasing.expo.animation(BYEDuration.swipe) }
    /// Rows that appear one after another.
    static func stagger(_ index: Int, reduce: Bool) -> Animation? {
        reduce ? nil : BYEEasing.expo.animation(BYEDuration.slide).delay(Double(index) * BYEDuration.stagger)
    }
}

/// Fades content in once, after an optional stagger, like the mockup's `.in` class.
struct FadeIn: ViewModifier {
    var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    func body(content: Content) -> some View {
        content.opacity(shown || reduceMotion ? 1 : 0)
            .onAppear { withAnimation(BYEMotion.stagger(index, reduce: reduceMotion)) { shown = true } }
    }
}

extension View {
    func fadeIn(_ index: Int = 0) -> some View { modifier(FadeIn(index: index)) }
}
