import SwiftUI
import ClasswiseCore

/// First launch, step one: the wordmark and what BYE is for.
struct WelcomeView: View {
    let onContinue: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 12) {
            SwipedWord(text: "BYE", size: 64)
            Text("Before You Enroll").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.secondary).fadeIn(2)
            Text("Find the class that fits your week.").font(BYEFont.display(30, bold: true))
                .multilineTextAlignment(.center).padding(.top, 8).fadeIn(3)
                .accessibilityAddTraits(.isHeader)
            Text("Every PCC section, seat and professor review in one spot. Made by a PCC student, for PCC students.")
                .font(.system(size: 15)).foregroundStyle(Palette.body).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).fadeIn(4)
            Button("Let’s go →", action: onContinue).buttonStyle(StickerButtonStyle())
                .keyboardShortcut(.defaultAction).focused($focused).padding(.top, 12).fadeIn(5)
        }
        .frame(maxWidth: 460)
        .onAppear { focused = true }
    }
}

/// First launch, step two: the student's first name beside an ID card that fills in as they type.
/// The name stays on this Mac, and Skip is always available.
struct NameStepView: View {
    let term: String?
    let onFinish: (String) -> Void
    @State private var name: String
    @State private var error = ""
    @FocusState private var fieldFocused: Bool

    init(initialName: String, term: String?, onFinish: @escaping (String) -> Void) {
        self.term = term; self.onFinish = onFinish
        _name = State(initialValue: initialName)
    }

    var body: some View {
        HStack(spacing: 48) {
            VStack(alignment: .leading, spacing: 8) {
                Text("First things first. What should we call you?").font(BYEFont.display(28, bold: true))
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                Text("It stays on this computer. Promise.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    .padding(.bottom, 6)
                TextField("Your first name", text: $name)
                    .textFieldStyle(.plain).font(.system(size: 16)).textContentType(.givenName)
                    .padding(.horizontal, 14).frame(height: 46)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.ink, lineWidth: BYEBorder.control))
                    .overlay { if fieldFocused { RoundedRectangle(cornerRadius: 12).stroke(Palette.highlight.opacity(0.6), lineWidth: 3).padding(-3) } }
                    .focused($fieldFocused)
                    .onSubmit(submit)
                    .onChange(of: name) { _, value in
                        error = ""
                        if value.count > AppPreferences.maxNameLength { name = String(value.prefix(AppPreferences.maxNameLength)) }
                    }
                    .accessibilityLabel("Your name")
                Text(error).font(.system(size: 12)).foregroundStyle(Palette.signal).frame(minHeight: 16, alignment: .leading)
                    .accessibilityHidden(error.isEmpty)
                HStack(spacing: 6) {
                    Button("That’s me →", action: submit).buttonStyle(StickerButtonStyle())
                    Button("Skip") { onFinish("") }.buttonStyle(StickerButtonStyle(kind: .ghost))
                }
            }
            .frame(width: 320, alignment: .leading)
            StudentIDCard(name: AppPreferences.normalizedName(name), term: term)
        }
        .onAppear { DispatchQueue.main.async { fieldFocused = true } }
    }

    private func submit() {
        let value = AppPreferences.normalizedName(name)
        if value.isEmpty { show("Type a name, or skip for now.") }
        else if !AppPreferences.isValidName(value) { show("Use letters, spaces, hyphens or apostrophes.") }
        else { onFinish(value) }
    }
    private func show(_ message: String) {
        error = message
        AccessibilityNotification.Announcement(message).post()
    }
}

/// The tilted student ID card. It is decoration: the name field carries the accessible label.
struct StudentIDCard: View {
    let name: String
    let term: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    private var initial: String { name.first.map { String($0).uppercased() } ?? "?" }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BYERadius.lg)
        VStack(spacing: 0) {
            HStack {
                Text("BYE").font(BYEFont.display(16, bold: true))
                Spacer()
                Text("Student").font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Palette.paper).padding(.horizontal, 14).padding(.vertical, 10).background(Palette.ink)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text(initial).font(BYEFont.display(18, bold: true))
                        .frame(width: 46, height: 46).background(Palette.highlight, in: Circle())
                        .phaseAnimator([0, 1, 2], trigger: reduceMotion ? "" : initial) { content, phase in
                            content.scaleEffect(phase == 1 ? 0.85 : phase == 2 ? 1.08 : 1)
                                .rotationEffect(.degrees(phase == 1 ? -6 : phase == 2 ? 3 : 0))
                        } animation: { _ in .spring(response: 0.18, dampingFraction: 0.6) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name.isEmpty ? "Your name" : name).font(BYEFont.display(19, bold: true))
                            .lineLimit(2).minimumScaleFactor(0.8).frame(minHeight: 24, alignment: .leading)
                        Text("Pasadena City College").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                }
                HStack {
                    if let term { Text("Term · \(term)") }
                    Spacer()
                    Text("BYE-0001").font(BYEFont.mono(11))
                }
                .font(.system(size: 11)).foregroundStyle(Palette.secondary).padding(.top, 14)
                HStack(spacing: 0) {
                    ForEach(0..<34, id: \.self) { index in
                        Rectangle().fill(Palette.ink).frame(width: [1, 2, 1, 3, 1, 2][index % 6])
                            .padding(.trailing, CGFloat(index % 4))
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 24).padding(.top, 8)
            }
            .padding(14)
        }
        .frame(width: 260)
        .background(Palette.card)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.ink, lineWidth: BYEBorder.sticker))
        .background(shape.fill(Palette.ink).offset(x: 4, y: 4))
        .rotationEffect(.degrees(hovering || reduceMotion ? 0 : -BYETilt.idCard))
        .animation(BYEMotion.spring(reduce: reduceMotion), value: hovering)
        .onHover { hovering = $0 }
        .accessibilityHidden(true)
    }
}

/// A word with the yellow highlighter swipe drawn in from the left once.
struct SwipedWord: View {
    let text: String
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false
    var body: some View {
        Text(text).font(BYEFont.display(size, bold: true)).padding(.horizontal, size * 0.05)
            .background(alignment: .bottom) {
                UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 2, bottomTrailingRadius: 5, topTrailingRadius: 2)
                    .fill(Palette.highlight).frame(height: size * 0.38)
                    .scaleEffect(x: drawn || reduceMotion ? 1 : 0, anchor: .leading)
                    .rotationEffect(.degrees(-1)).offset(y: -size * 0.04)
            }
            .onAppear { withAnimation(BYEMotion.swipe(reduce: reduceMotion)?.delay(0.25)) { drawn = true } }
            .accessibilityLabel(text)
    }
}

/// A short burst of ink and yellow paper when the first run finishes. Nothing runs with Reduce Motion.
struct ConfettiBurst: View {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var pieces: [Piece] = []

    struct Piece {
        let angle: Double, speed: Double, spin: Double, life: Double, wide: Bool, yellow: Bool
    }

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { context in
            Canvas { canvas, size in
                guard let start else { return }
                let elapsed = context.date.timeIntervalSince(start)
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.42)
                for piece in pieces {
                    let progress = min(1, elapsed / piece.life), eased = 1 - pow(1 - progress, 3)
                    guard progress < 1 else { continue }
                    var layer = canvas
                    layer.opacity = 1 - progress
                    layer.translateBy(x: origin.x + cos(piece.angle) * piece.speed * eased,
                                      y: origin.y + (sin(piece.angle) * piece.speed * 0.7 + 180) * eased)
                    layer.rotate(by: .degrees(piece.spin * eased))
                    let rect = piece.wide ? CGRect(x: -4, y: -6, width: 8, height: 12) : CGRect(x: -3, y: -4, width: 6, height: 8)
                    layer.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(piece.yellow ? Palette.highlight : Palette.ink))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            guard !reduceMotion else { return }
            pieces = (0..<46).map { index in
                Piece(angle: .random(in: 0..<(2 * .pi)), speed: .random(in: 120...340), spin: .random(in: 0...720),
                      life: BYEDuration.confetti * .random(in: 0.8...1.2), wide: index % 3 == 0, yellow: index % 2 == 0)
            }
            let burst = Date(); start = burst
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(BYEDuration.confetti * 1.3))
                if start == burst { start = nil; pieces = [] }
            }
        }
    }
}
