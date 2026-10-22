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
}

private enum TutorialStep: Int, CaseIterable {
    case daily, play, consonants, first, second

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
        case .consonants: "Les voyelles ont disparu"
        case .first: "Ça peut être TROU…"
        case .second: "… mais aussi AUTEUR !"
        }
    }
    var message: String {
        switch self {
        case .daily: "Un nouveau mot chaque jour, le même pour tout le monde. Une seule partie, avec un chrono."
        case .play: "Le chrono démarre et les consonnes du mot apparaissent. Voyons un exemple."
        case .consonants: "Il ne reste que les consonnes, dans l’ordre. À vous de remettre les voyelles pour retrouver le mot."
        case .first: "On glisse O et U entre les consonnes : T, R… TROU."
        case .second: "Attention, une voyelle peut aussi se cacher au début ou à la fin. L’indice vous aide à trancher : « Il a écrit le livre. »"
        }
    }
    /// The word revealed under the consonants, vowels in gold.
    var word: String? {
        switch self {
        case .first: "TROU"
        case .second: "AUTEUR"
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
                Button(step == .second ? "À vous de jouer" : "Suivant") { next() }
                    .buttonStyle(PrimaryPillStyle(height: 48)).frame(width: step == .second ? 190 : 130)
            }.padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 28, padding: 20)
        .id(step)
        .transition(.opacity)
    }

    /// TR, then the word with its vowels sliding in.
    private var example: some View {
        VStack(spacing: 0) {
            SectionKicker(text: "Exemple").frame(maxWidth: .infinity, alignment: .leading)
            Text(Tutorial.consonants).font(Typo.serif(72)).tracking(6).padding(.top, 6)
                .accessibilityLabel("Consonnes : T, R")
            Rectangle().fill(Palette.line).frame(height: 1).padding(.vertical, 16)
            Group {
                if let word = step.word {
                    VowelWord(word: word, font: .system(size: 34, weight: .heavy), delay: 0.25, once: true)
                        .tracking(2.4).id(word)
                } else {
                    Text("? ? ?").font(.system(size: 34, weight: .heavy)).tracking(4).foregroundStyle(Palette.tertiary)
                        .accessibilityLabel("Mot à trouver")
                }
            }.frame(height: 44)
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
