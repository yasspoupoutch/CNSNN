import SwiftUI
import CNSNNCore

/// The places on the home page the first-launch tutorial points at.
enum TutorialTarget: Hashable { case daily, play }

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
    static let theme = "Général · Facile"
}

private enum TutorialStep: Int, CaseIterable {
    case daily, play, consonants, first, second, theme

    var target: TutorialTarget? {
        switch self {
        case .daily: .daily
        case .play: .play
        default: nil
        }
    }
    var title: String {
        switch self {
        case .daily: "Le mot du jour"
        case .play: "Appuyez sur Jouer"
        case .consonants: "J’ai enlevé les voyelles"
        case .first: "Ça peut être TROU…"
        case .second: "… mais aussi AUTEUR !"
        case .theme: "Le thème peut vous aider"
        }
    }
    var message: String {
        switch self {
        case .daily: "Un nouveau mot chaque jour, le même pour tout le monde. Une seule partie, avec un chrono."
        case .play: "Le chrono démarre et les consonnes du mot apparaissent. Voyons un exemple."
        case .consonants: "Il ne reste que les consonnes de ce mot, dans l’ordre. À vous de retrouver le mot !"
        case .first: "Les voyelles O et U reviennent se glisser entre T et R."
        case .second: "On repart de TR : cette fois, des voyelles se glissent aussi avant le T. Alors, TROU ou AUTEUR ?"
        case .theme: "Pendant la partie, il est écrit en haut, sous le titre, avec la difficulté. Et si vous séchez, l’indice tranche : « Il a écrit le livre. »"
        }
    }
    /// The word revealed under the consonants, vowels in gold.
    var word: String? {
        switch self {
        case .first: "TROU"
        case .second, .theme: "AUTEUR"
        default: nil
        }
    }
}

/// First-launch tutorial: dims the app, lights up the daily card then its Jouer button,
/// and ends on an example (TR: TROU, but also AUTEUR).
struct TutorialOverlay: View {
    var anchors: [TutorialTarget: Anchor<CGRect>]
    var finish: () -> Void
    @State private var step = TutorialStep.daily
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let hole = spotlight(in: proxy)
            ZStack(alignment: .topLeading) {
                SpotlightShape(hole: hole.rect, radius: hole.radius)
                    .fill(Color.black.opacity(0.76), style: FillStyle(eoFill: true))
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .accessibilityHidden(true)
                if step == .play, hole.rect.width > 0 { playButton(hole) }
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button("Passer") { close() }
                            .scaledFont(15, .semibold).foregroundStyle(Palette.secondary)
                            .padding(.horizontal, 16).frame(minHeight: 44)
                            .accessibilityIdentifier("tutorial.skip")
                    }
                    .padding(.top, proxy.safeAreaInsets.top).padding(.horizontal, 8)
                    if step.target == nil {
                        Spacer(minLength: 12)
                        example.padding(.horizontal, 26)
                        callout.padding(.horizontal, 26).padding(.top, 18)
                        Spacer(minLength: 12)
                    } else {
                        callout
                            .padding(.horizontal, 20)
                            .padding(.top, max(0, hole.rect.maxY + 18 - proxy.safeAreaInsets.top - 44))
                        Spacer(minLength: 0)
                    }
                }
                .padding(.bottom, proxy.safeAreaInsets.bottom + 12)
                .frame(maxWidth: CNSNNTheme.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .animation(reduceMotion ? nil : CNSNNTheme.ease, value: step)
        }
        .ignoresSafeArea()
        .accessibilityAddTraits(.isModal)
        .onAppear { titleFocused = true }
    }

    // MARK: Spotlight

    private func spotlight(in proxy: GeometryProxy) -> (rect: CGRect, radius: CGFloat) {
        guard let target = step.target, let anchor = anchors[target] else {
            return (CGRect(x: proxy.size.width / 2, y: proxy.size.height / 2, width: 0, height: 0), 0)
        }
        let frame = proxy[anchor]
        switch target {
        case .daily: return (frame.insetBy(dx: -6, dy: -6), 38)
        case .play: return (frame.insetBy(dx: -8, dy: -8), frame.height / 2 + 8)
        }
    }

    /// The lit Jouer button can be tapped to go on, like the real one.
    private func playButton(_ hole: (rect: CGRect, radius: CGFloat)) -> some View {
        Button { next() } label: {
            RoundedRectangle(cornerRadius: hole.radius, style: .continuous)
                .strokeBorder(Palette.accent, lineWidth: 2)
                .modifier(Pulse(active: !reduceMotion))
                .contentShape(RoundedRectangle(cornerRadius: hole.radius, style: .continuous))
        }
        .buttonStyle(PressStyle(scale: 0.96))
        .frame(width: hole.rect.width, height: hole.rect.height)
        .position(x: hole.rect.midX, y: hole.rect.midY)
        .accessibilityLabel("Jouer")
        .accessibilityIdentifier("tutorial.play")
    }

    // MARK: Text

    private var callout: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach(TutorialStep.allCases, id: \.self) { item in
                    Capsule().fill(item == step ? Palette.accent : Palette.fill2)
                        .frame(width: item == step ? 18 : 6, height: 6)
                }
            }
            .accessibilityElement().accessibilityLabel("Étape \(step.rawValue + 1) sur \(TutorialStep.allCases.count)")
            Text(step.title).scaledFont(24, .bold).tracking(-0.3).padding(.top, 14)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            Text(step.message).scaledFont(15).foregroundStyle(Palette.secondary).padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if step != .daily {
                    Button("Retour") { back() }
                        .scaledFont(15, .semibold).foregroundStyle(Palette.secondary)
                        .frame(minHeight: 44)
                }
                Spacer()
                Button(step == .theme ? "À vous de jouer" : "Suivant") { next() }
                    .buttonStyle(PrimaryPillStyle(height: 48)).frame(width: step == .theme ? 190 : 130)
            }.padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 28, padding: 20)
        .id(step)
        .transition(.opacity)
    }

    /// Like the top of a game: the title, the theme and the difficulty, then the word. TR alone, then the
    /// vowels slide into it: TROU, back to TR, then AUTEUR. Tap the word to see it again.
    private var example: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("Exemple").scaledFont(16, .semibold)
                Text(Tutorial.theme).scaledFont(12, step == .theme ? .semibold : .regular)
                    .foregroundStyle(step == .theme ? Palette.accent : Palette.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .overlay {
                Capsule().strokeBorder(Palette.accent, lineWidth: 2)
                    .modifier(Pulse(active: !reduceMotion))
                    .opacity(step == .theme ? 1 : 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Exemple, thème : " + Tutorial.theme)
            // The theme step keeps AUTEUR on screen without playing it again.
            MorphWord(word: step.word, from: step == .second ? TutorialStep.first.word : nil)
                .id(step == .theme ? .second : step)
                .frame(maxWidth: .infinity, minHeight: 96)
                .padding(.top, 8)
        }
        .glassCard(radius: 30, padding: 22)
    }

    private func next() {
        Haptics.selection()
        guard let following = TutorialStep(rawValue: step.rawValue + 1) else { close(); return }
        step = following
        titleFocused = true
    }
    private func back() {
        Haptics.selection()
        if let previous = TutorialStep(rawValue: step.rawValue - 1) { step = previous }
        titleFocused = true
    }
    private func close() {
        Haptics.success()
        finish()
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
private struct MorphWord: View {
    var word: String?
    var from: String?
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
    private func letters(_ text: String, progress: (Int) -> CGFloat) -> some View {
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
        .font(Typo.serif(68)).tracking(3).lineLimit(1).fixedSize()
    }
    private static func smooth(_ x: Double) -> CGFloat { let t = min(max(x, 0), 1); return CGFloat(t * t * (3 - 2 * t)) }
}
