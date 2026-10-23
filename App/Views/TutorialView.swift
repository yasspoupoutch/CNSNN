import SwiftUI
import CNSNNCore

/// The places the first-launch tutorial points at: the daily card on the home page, then the real
/// Mot du jour page (played with an example word, never the real one).
enum TutorialTarget: Hashable { case daily, play, title, clock, board, hint }

/// Frames of the tutorial targets, read by the overlay above the whole shell.
struct TutorialAnchors: PreferenceKey {
    static let defaultValue: [TutorialTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TutorialTarget: Anchor<CGRect>], nextValue: () -> [TutorialTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func tutorialTarget(_ target: TutorialTarget) -> some View {
        transformAnchorPreference(key: TutorialAnchors.self, value: .bounds) { $0[target] = $1 }
    }
}

enum Tutorial {
    static let seenKey = "cnsnn.tutorialSeen"
    /// Once, for a new player who has never played. Interface tests ask for it with --tutorial.
    @MainActor static func shouldShow(seen: Bool, _ state: AppState) -> Bool {
        if RuntimeFlags.isTesting { return ProcessInfo.processInfo.arguments.contains("--tutorial") }
        return !seen && state.progress.attempts.isEmpty && state.inviteCode == nil
    }
    /// A fixed example, never the real daily word, so the tutorial cannot give anything away.
    static let consonants = "TR"
    static let card = Card(id: "seed-tutorial", wordFull: "Auteur", hint: "Il a écrit le livre.", category: .general, difficulty: .easy)
}

enum TutorialStep: Int, CaseIterable {
    case play, consonants, first, second, top, help

    var title: String {
        switch self {
        case .play: "Le mot du jour"
        case .consonants: "J’ai enlevé les voyelles"
        case .first: "Ça peut être TROU…"
        case .second: "… ou AUTEUR…"
        case .top: "Le thème et le chrono"
        case .help: "Si vous ne trouvez pas…"
        }
    }
    var message: String {
        switch self {
        case .play: "Un nouveau mot chaque jour, le même pour tous. Appuyez sur Jouer !"
        case .consonants: "Il ne reste que les consonnes, dans l’ordre. Ça peut être un mot, une ville, un pays, un film, un joueur… À vous de le retrouver !"
        case .first: "Les voyelles O et U reviennent se glisser entre T et R."
        case .second: "On repart de TR : cette fois, des voyelles se glissent aussi avant le T. Plusieurs mots sont possibles !"
        case .top: "Sous les consonnes, le thème du mot pour vous mettre sur la piste. Le chrono, en haut à droite, part dès que vous appuyez sur Jouer."
        case .help: "… prenez un indice ! Appuyez sur Indice (+1 min sur le mot du jour)."
        }
    }
    /// What the board shows: the consonants, or the word with its vowels sliding in.
    var word: String? {
        switch self {
        case .first: "TROU"
        case .second: "AUTEUR"
        default: nil
        }
    }
    var target: TutorialTarget {
        switch self {
        case .play: .daily
        case .consonants, .first, .second: .board
        case .top: .title
        case .help: .hint
        }
    }
}

/// The tutorial's progress on the Mot du jour page, shared by the board (which morphs the example word)
/// and the overlay.
@MainActor @Observable final class TutorialDemo {
    var step = TutorialStep.consonants
    /// The last step: Indice was tapped, the hint shows and AUTEUR slides in.
    var hintShown = false
    var word: String? { hintShown ? "AUTEUR" : step.word }
    var from: String? { step == .second && !hintShown ? TutorialStep.first.word : nil }
}

/// First step, on the home page: the app blurred and dimmed around the daily card, Jouer ringed in
/// pulsing gold. Jouer is the only way on: it opens the real Mot du jour page for the rest.
struct TutorialOverlay: View {
    var anchors: [TutorialTarget: Anchor<CGRect>]
    var play: () -> Void
    var skip: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let hole = anchors[.daily].map { proxy[$0].insetBy(dx: -6, dy: -6) } ?? .zero
            TutorialStage(hole: hole, radius: 38, size: proxy.size, skip: skip) {
                TutorialBubble(step: .play)
            } extra: {
                if let anchor = anchors[.play] { playButton(proxy[anchor]) }
            }
        }
    }

    /// The Jouer button gets a pulsing gold ring and opens the game page, like the real one.
    private func playButton(_ frame: CGRect) -> some View {
        let ring = frame.insetBy(dx: -6, dy: -6)
        return Button { Haptics.selection(); play() } label: {
            Capsule()
                .strokeBorder(Palette.accent, lineWidth: 2.5)
                .modifier(Pulse(active: !reduceMotion))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle(scale: 0.96))
        .frame(width: ring.width, height: ring.height)
        .position(x: ring.midX, y: ring.midY)
        .accessibilityLabel("Jouer")
        .accessibilityIdentifier("tutorial.play")
    }
}

/// The rest of the tutorial, over the real Mot du jour page: the consonants, the vowels sliding in,
/// the theme and the clock, then Indice, which really reveals the example's hint.
struct TutorialGameOverlay: View {
    var anchors: [TutorialTarget: Anchor<CGRect>]
    var demo: TutorialDemo
    /// true: "À vous de jouer", the real daily game opens next.
    var finish: (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let spot = spotlight(proxy)
            TutorialStage(hole: spot.rect, radius: spot.radius, size: proxy.size, passThrough: demo.step == .help && !demo.hintShown, skip: { finish(false) }) {
                TutorialBubble(step: demo.step, hintShown: demo.hintShown, back: back, next: next)
            } extra: {
                if demo.step == .help && !demo.hintShown, let anchor = anchors[.hint] { hintButton(proxy[anchor]) }
            }
        }
        .animation(reduceMotion ? nil : CNSNNTheme.ease, value: demo.step)
        .animation(reduceMotion ? nil : CNSNNTheme.ease, value: demo.hintShown)
    }

    private func spotlight(_ proxy: GeometryProxy) -> (rect: CGRect, radius: CGFloat) {
        func frame(_ target: TutorialTarget) -> CGRect? { anchors[target].map { proxy[$0] } }
        switch demo.step {
        case .top:
            // The theme line under the board; the bubble names the clock.
            let theme = frame(.title) ?? .zero
            return (theme.insetBy(dx: -8, dy: -8), theme.height / 2 + 8)
        case .help where !demo.hintShown:
            let hint = frame(.hint) ?? .zero
            return (hint.insetBy(dx: -8, dy: -8), hint.height / 2 + 8)
        default:
            return ((frame(.board) ?? .zero).insetBy(dx: -12, dy: -10), 28)
        }
    }

    /// Indice blinks in gold; the tap goes through to the real button, which reveals the hint as in a game.
    private func hintButton(_ frame: CGRect) -> some View {
        let ring = frame.insetBy(dx: -6, dy: -6)
        return Capsule().fill(Palette.accentSoft).modifier(Pulse(active: !reduceMotion))
            .overlay(Capsule().strokeBorder(Palette.accent, lineWidth: 2.5).modifier(Pulse(active: !reduceMotion)))
            .frame(width: ring.width, height: ring.height)
            .position(x: ring.midX, y: ring.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func next() {
        Haptics.selection()
        if demo.step == .help { finish(true); return }
        if let following = TutorialStep(rawValue: demo.step.rawValue + 1) { demo.step = following; demo.hintShown = false }
    }
    private func back() {
        Haptics.selection()
        guard demo.step != .consonants, let previous = TutorialStep(rawValue: demo.step.rawValue - 1) else { return }
        demo.step = previous; demo.hintShown = false
    }
}

/// The screen behind blurred and dimmed, a rounded hole over the part being explained, "Passer" at the
/// top, and the bubble right under the hole (or above it, when the hole is low on the screen).
private struct TutorialStage<Bubble: View, Extra: View>: View {
    var hole: CGRect
    var radius: CGFloat
    var size: CGSize
    /// true: a tap in the hole reaches the real control under it (Indice).
    var passThrough = false
    var skip: () -> Void
    @ViewBuilder var bubble: () -> Bubble
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        let below = hole.midY < size.height * 0.55
        let arrowX = min(max(hole.midX, 40), size.width - 40)
        ZStack(alignment: .topLeading) {
            // Blurred and dimmed everywhere but the hole, past the safe area; taps outside go nowhere.
            let margin: CGFloat = 120
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(0.55)
            }
            .frame(width: size.width + 2 * margin, height: size.height + 2 * margin)
            .mask(SpotlightShape(hole: hole.offsetBy(dx: margin, dy: margin), radius: radius).fill(style: FillStyle(eoFill: true)))
            .contentShape(passThrough ? AnyShape(SpotlightShape(hole: hole.offsetBy(dx: margin, dy: margin), radius: radius)) : AnyShape(Rectangle()), eoFill: passThrough)
            .position(x: size.width / 2, y: size.height / 2)
            .onTapGesture {}
            .accessibilityHidden(true)
            // A thin light edge around the hole.
            RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                .frame(width: max(0, hole.width), height: max(0, hole.height))
                .position(x: hole.midX, y: hole.midY)
                .allowsHitTesting(false)
            extra()
            VStack(spacing: 0) {
                if !below { Spacer(minLength: 0) }
                bubble()
                    .modifier(BubbleArrow(up: below, x: arrowX - 16))
                    .padding(.horizontal, 16)
                    .padding(below ? .top : .bottom, below ? hole.maxY + 14 : size.height - hole.minY + 14)
                if below { Spacer(minLength: 0) }
            }
            .frame(width: size.width, height: size.height)
            .transition(.opacity)
            Button("Passer", action: skip)
                .scaledFont(15, .semibold).foregroundStyle(Palette.foreground)
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(Capsule().fill(Color.black.opacity(0.35)))
                .padding(.trailing, 12).padding(.top, 4)
                .frame(width: size.width, alignment: .trailing)
                .accessibilityIdentifier("tutorial.skip")
        }
        .accessibilityAddTraits(.isModal)
    }
}

/// The tutorial's speech bubble: light, with a shadow and an arrow toward the hole, so it reads as a
/// note laid over the app and not as one of its cards.
struct TutorialBubble: View {
    var step: TutorialStep
    var hintShown = false
    var back: (() -> Void)? = nil
    var next: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach(TutorialStep.allCases, id: \.self) { item in
                    Capsule().fill(item == step ? Palette.ink : Palette.ink.opacity(0.2))
                        .frame(width: item == step ? 18 : 6, height: 6)
                }
            }
            .accessibilityElement().accessibilityLabel("Étape \(step.rawValue + 1) sur \(TutorialStep.allCases.count)")
            Text(step.title).scaledFont(22, .bold).tracking(-0.3).foregroundStyle(Palette.ink).padding(.top, 12)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            Text(step == .help && hintShown ? "« Il a écrit le livre. » : c’est AUTEUR ! À vous de trouver le mot du jour." : step.message)
                .scaledFont(15).foregroundStyle(Palette.ink.opacity(0.75)).padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
            // On the home page, Jouer is the only way on; on the hint step, Indice first.
            if let next, step != .help || hintShown {
                HStack {
                    if let back, step != .consonants {
                        Button("Retour", action: back)
                            .scaledFont(15, .semibold).foregroundStyle(Palette.ink.opacity(0.6))
                            .frame(minHeight: 44)
                    }
                    Spacer()
                    // The button breathes, so it is clear a tap goes on.
                    Button(step == .help ? "À vous de jouer" : "Suivant", action: next)
                        .buttonStyle(PrimaryPillStyle(height: 46)).frame(width: step == .help ? 190 : 130)
                        .modifier(Breathe(active: !reduceMotion))
                }.padding(.top, 14)
            } else if let back, step == .help {
                Button("Retour", action: back)
                    .scaledFont(15, .semibold).foregroundStyle(Palette.ink.opacity(0.6))
                    .frame(minHeight: 44).padding(.top, 8)
            }
        }
        .frame(maxWidth: CNSNNTheme.readableWidth, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.foreground))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
        .id("\(step)-\(hintShown)")
        .onAppear { titleFocused = true }
    }
}

/// The bubble's little arrow, pointing up at the hole (bubble below it) or down (bubble above it).
private struct BubbleArrow: ViewModifier {
    var up: Bool
    var x: CGFloat
    func body(content: Content) -> some View {
        content.overlay(alignment: up ? .topLeading : .bottomLeading) {
            Triangle(up: up).fill(Palette.foreground)
                .frame(width: 20, height: 10)
                .offset(x: max(14, x - 10), y: up ? -9 : 9)
                .accessibilityHidden(true)
        }
    }
}

/// The little arrow of a speech bubble, pointing up or down.
struct Triangle: Shape {
    var up: Bool
    func path(in rect: CGRect) -> Path {
        var path = Path()
        if up {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.midX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.closeSubpath()
        return path
    }
}

/// The dimmed screen with a rounded hole over the part being explained.
private struct SpotlightShape: Shape {
    var hole: CGRect
    var radius: CGFloat
    var animatableData: AnimatablePair<CGRect.AnimatableData, CGFloat> {
        get { AnimatablePair(hole.animatableData, radius) }
        set { hole.animatableData = newValue.first; radius = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -40, dy: -40))
        if hole.width > 1 {
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        }
        return path
    }
}

/// A slow breathing ring, to show where to tap.
private struct Pulse: ViewModifier {
    var active: Bool
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 0.35 : 1)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

/// The example word, one big serif line: the consonants stay put and the gold vowels slide in between
/// them. With `from`, that word's vowels first slide back out, so TROU turns back into TR before AUTEUR.
struct MorphWord: View {
    var word: String?
    var from: String?
    var size: CGFloat = 68
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    private static let out = 0.45, pause = 0.4, lead = 0.35, grow = 0.45, stagger = 0.1
    private var still: Bool { reduceMotion || RuntimeFlags.isTesting }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { context in
            let time = context.date.timeIntervalSince(start)
            let back = from == nil ? 0 : Self.out + Self.pause
            if let from, !still, time < back {
                letters(from) { _ in 1 - Self.smooth(time / Self.out) }
            } else {
                letters(word ?? Tutorial.consonants) { index in
                    still ? 1 : Self.smooth((time - back - Self.lead - Double(index) * Self.stagger) / Self.grow)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { start = Date() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(word ?? "Consonnes : T, R")
        .accessibilityAddTraits(.isStaticText)
    }
    private func letters(_ text: String, progress: @escaping (Int) -> CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                if Vowels.contains(character) {
                    let value = progress(index)
                    CollapseLayout(progress: value) { Text(String(character)).foregroundStyle(Palette.accent) }
                        .opacity(value).clipped()
                } else {
                    Text(String(character))
                }
            }
        }
        .font(Typo.serif(size)).tracking(3).lineLimit(1).fixedSize()
    }
    private static func smooth(_ x: Double) -> CGFloat { let t = min(max(x, 0), 1); return CGFloat(t * t * (3 - 2 * t)) }
}

/// A gentle grow and shrink, so the button to tap catches the eye.
private struct Breathe: ViewModifier {
    var active: Bool
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? 1.06 : 1)
            .shadow(color: Palette.accent.opacity(on ? 0.55 : 0), radius: on ? 14 : 0)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { on = true }
            }
    }
}
