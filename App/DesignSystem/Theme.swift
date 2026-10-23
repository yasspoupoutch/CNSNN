import SwiftUI
import CNSNNCore
import UIKit

/// Design tokens from the Claude Design "CNSNN — Liquid Glass" prototype (dark theme).
enum Palette {
    static let background = Color(red: 0.024, green: 0.027, blue: 0.047)
    static let backgroundTop = Color(red: 0.071, green: 0.078, blue: 0.149)
    static let foreground = Color(red: 0.957, green: 0.961, blue: 0.973)
    static let secondary = foreground.opacity(0.64)
    /// 0.56 keeps small text above a 4.5:1 contrast ratio on the dark background.
    static let tertiary = foreground.opacity(0.56)
    static let focusRing = foreground.opacity(0.6)
    static let fill1 = Color.white.opacity(0.08)
    static let fill2 = Color.white.opacity(0.14)
    static let glassTop = Color.white.opacity(0.14)
    static let glassBottom = Color.white.opacity(0.05)
    static let glassBorder = Color.white.opacity(0.16)
    static let glassHighlight = Color.white.opacity(0.38)
    static let glassShadow = Color.black.opacity(0.3)
    static let line = Color.white.opacity(0.07)
    static let accent = Color(red: 1.0, green: 0.777, blue: 0.355)
    static let accentTop = Color(red: 1.0, green: 0.837, blue: 0.45)
    static let accentBottom = Color(red: 0.963, green: 0.721, blue: 0.303)
    static let accentSoft = accent.opacity(0.14)
    static let onAccent = Color(red: 0.102, green: 0.078, blue: 0.024)
    static let mint = Color(red: 0.352, green: 0.902, blue: 0.775)
    static let red = Color(red: 1.0, green: 0.529, blue: 0.523)
    static let redSoft = Color(red: 0.992, green: 0.448, blue: 0.451).opacity(0.16)
    static let tabOn = Color.white.opacity(0.17)
    static let dim = Color.black.opacity(0.42)
    static let sheetTop = Color(red: 0.157, green: 0.165, blue: 0.212).opacity(0.55)
    static let sheetBottom = Color(red: 0.078, green: 0.082, blue: 0.11).opacity(0.74)
    static let surface = Color(red: 0.09, green: 0.094, blue: 0.122)
    static let ink = Color(red: 0.043, green: 0.047, blue: 0.063)
    static let avatars: [Color] = [
        Color(red: 0.954, green: 0.726, blue: 0.299), Color(red: 0.288, green: 0.85, blue: 0.725),
        Color(red: 0.668, green: 0.598, blue: 1.0), Color(red: 0.951, green: 0.541, blue: 0.743),
        Color(red: 0.366, green: 0.753, blue: 0.963),
    ]
    static func avatar(_ index: Int) -> Color { avatars[((index % avatars.count) + avatars.count) % avatars.count] }
}

enum CNSNNTheme {
    static let background = Palette.background
    static let surface = Palette.surface
    static let accent = Palette.accent
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.84)
    static let ease = Animation.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.45)
    static let avatarKey = "cnsnn.avatarIndex"
    /// Widest the content gets: on a wide screen (the unfolded iPhone Duo) it stays phone-shaped, centered.
    static let readableWidth: CGFloat = 560
}

extension View {
    /// Caps the width at `CNSNNTheme.readableWidth` and centers it; no effect on a phone.
    func readableWidth() -> some View {
        frame(maxWidth: CNSNNTheme.readableWidth).frame(maxWidth: .infinity)
    }
}

enum Typo {
    /// Instrument Serif (SIL OFL), bundled in App/Resources/Fonts. Falls back to the system font if missing.
    static func serif(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom("InstrumentSerif-Regular", size: size, relativeTo: style)
    }
    static func serifItalic(_ size: CGFloat, relativeTo style: Font.TextStyle = .title3) -> Font {
        .custom("InstrumentSerif-Italic", size: size, relativeTo: style)
    }
    static let kicker = Font.system(size: 12, weight: .bold)
    /// Fraunces Black (SIL OFL, soft and "wonky" cut), reserved for the game's name.
    static func wordmark(_ size: CGFloat) -> Font { .custom("Fraunces-Black", fixedSize: size) }
}

/// System font at the prototype's point size that still follows the user's text size setting.
struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    init(size: CGFloat, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: Self.style(for: size))
        self.weight = weight
    }
    func body(content: Content) -> some View { content.font(.system(size: size, weight: weight)) }
    /// The text style whose default size is closest, so each size grows at the system's pace.
    private static func style(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: .caption2
        case ..<12.5: .caption
        case ..<13.5: .footnote
        case ..<15.5: .subheadline
        case ..<16.5: .callout
        case ..<19.5: .body
        case ..<21: .title3
        case ..<25: .title2
        case ..<31: .title
        default: .largeTitle
        }
    }
}

extension View {
    func scaledFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight))
    }
    /// Grows the tappable area to Apple's 44 pt minimum without changing how the control looks.
    func hitTarget() -> some View {
        frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }
}

/// Generators are kept and prepared, so every tap answers without the first-use delay.
@MainActor enum Haptics {
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let keyGenerator = UIImpactFeedbackGenerator(style: .light)
    static func selection() { selectionGenerator.selectionChanged(); selectionGenerator.prepare() }
    static func success() { notificationGenerator.notificationOccurred(.success); notificationGenerator.prepare() }
    static func failure() { notificationGenerator.notificationOccurred(.warning); notificationGenerator.prepare() }
    static func retry() { softGenerator.impactOccurred(); softGenerator.prepare() }
    /// Letter keys: a very light tap, like the system keyboard.
    static func key() { keyGenerator.impactOccurred(intensity: 0.55); keyGenerator.prepare() }
}

enum Vowels {
    static func contains(_ character: Character) -> Bool {
        let folded = String(character).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR")).uppercased()
        return folded.contains { "AEIOUY".contains($0) } || "ŒÆœæ".contains(character)
    }
}

// MARK: - Background

/// Slow drifting colour blobs behind the glass, as in the prototype.
struct AmbientBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false
    private struct Blob {
        var color: Color, x: CGFloat, y: CGFloat, size: CGFloat
        var dx: CGFloat, dy: CGFloat, from: CGFloat, to: CGFloat, duration: Double
    }
    /// Two cool tones only: gold belongs to the vowels.
    private let blobs = [
        Blob(color: Color(red: 0.349, green: 0.244, blue: 0.779), x: -80, y: -60, size: 360, dx: 90, dy: 140, from: 1, to: 1.25, duration: 16),
        Blob(color: Color(red: 0.0, green: 0.492, blue: 0.526), x: 170, y: 420, size: 360, dx: -110, dy: -120, from: 1.1, to: 0.9, duration: 19),
    ]
    /// Dimmer behind the game board, so the consonants are what the eye finds.
    var dimmed = false
    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / 390
            ZStack(alignment: .topLeading) {
                RadialGradient(colors: [Palette.backgroundTop, Palette.background], center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: geo.size.height * 0.7)
                ForEach(blobs.indices, id: \.self) { index in
                    let blob = blobs[index]
                    // A radial fade looks like the blurred disc of the prototype without a live blur pass every frame.
                    Circle().fill(RadialGradient(colors: [blob.color, blob.color.opacity(0.55), blob.color.opacity(0)], center: .center,
                                                 startRadius: 0, endRadius: (blob.size / 2 + 70) * scale))
                        .frame(width: (blob.size + 140) * scale, height: (blob.size + 140) * scale)
                        .padding(-70 * scale)
                        .opacity(dimmed ? 0.28 : 0.5)
                        .scaleEffect(drift ? blob.to : blob.from)
                        .offset(x: (blob.x + (drift ? blob.dx : 0)) * scale, y: (blob.y + (drift ? blob.dy : 0)) * scale)
                        .animation(reduceMotion ? nil : .easeInOut(duration: blob.duration).repeatForever(autoreverses: true), value: drift)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(CNSNNTheme.ease, value: dimmed)
        .onAppear { if !reduceMotion && !RuntimeFlags.isTesting && !ProcessInfo.processInfo.isLowPowerModeEnabled { drift = true } }
    }
}

// MARK: - Glass surfaces

struct GlassSurface: ViewModifier {
    var radius: CGFloat
    var padding: CGFloat
    var prominent: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.padding(padding)
            .background {
                if reduceTransparency {
                    shape.fill(Palette.surface)
                } else if prominent {
                    shape.fill(.ultraThinMaterial)
                        .overlay(shape.fill(LinearGradient(colors: [Palette.glassTop, Palette.glassBottom], startPoint: .top, endPoint: .bottom)))
                } else {
                    shape.fill(.ultraThinMaterial.opacity(0.6)).overlay(shape.fill(Palette.fill1))
                }
            }
            .overlay(shape.strokeBorder(LinearGradient(colors: [Palette.glassHighlight, Palette.glassBorder, Palette.glassBorder], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: prominent ? Palette.glassShadow : .clear, radius: 20, y: 14)
    }
}

extension View {
    /// Main liquid-glass card (gradient, blur, top highlight, drop shadow).
    func glassCard(radius: CGFloat = 34, padding: CGFloat = 20) -> some View {
        modifier(GlassSurface(radius: radius, padding: padding, prominent: true))
    }
    /// Quieter frosted panel used for secondary blocks, tiles and lists.
    func glassPanel(radius: CGFloat = 26, padding: CGFloat = 18) -> some View {
        modifier(GlassSurface(radius: radius, padding: padding, prominent: false))
    }
    /// Small glass capsule (pills, chips, icon buttons). Native Liquid Glass on iOS 26 and later.
    func glassCapsule(interactive: Bool = false) -> some View {
        modifier(CapsuleGlass(interactive: interactive))
    }
}

struct CapsuleGlass: ViewModifier {
    var interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: Capsule())
        } else {
            content
                .background(Capsule().fill(reduceTransparency ? AnyShapeStyle(Palette.surface) : AnyShapeStyle(.ultraThinMaterial.opacity(0.6))).overlay(Capsule().fill(Palette.fill2)))
                .overlay(Capsule().strokeBorder(LinearGradient(colors: [Palette.glassHighlight, Palette.glassBorder], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        }
    }
}

// MARK: - Buttons

struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .animation(reduceMotion ? nil : CNSNNTheme.spring, value: configuration.isPressed)
    }
}

/// Gold pill, the prototype's primary action.
struct PrimaryPillStyle: ButtonStyle {
    var height: CGFloat = 56
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledFont(17, .semibold)
            .foregroundStyle(Palette.onAccent)
            .frame(maxWidth: .infinity).frame(minHeight: height)
            .background(Capsule().fill(Palette.accent))
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
            .shadow(color: Palette.accent.opacity(isEnabled ? 0.3 : 0), radius: 15, y: 10)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : CNSNNTheme.spring, value: configuration.isPressed)
    }
}

/// Glass pill, the prototype's secondary action.
struct GlassPillStyle: ButtonStyle {
    var height: CGFloat = 52
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledFont(16, .semibold)
            .foregroundStyle(Palette.foreground)
            .frame(maxWidth: .infinity).frame(minHeight: height)
            .glassCapsule()
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : CNSNNTheme.spring, value: configuration.isPressed)
    }
}

struct CircleIconButton: View {
    var symbol: String
    var label: String
    var action: () -> Void
    var body: some View {
        Button { Haptics.selection(); action() } label: {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.foreground)
                .frame(width: 44, height: 44)
                .glassCapsule()
        }.buttonStyle(PressStyle(scale: 0.92)).accessibilityLabel(label)
    }
}

/// Selectable chip (categories, difficulties, filters).
struct Chip: View {
    var title: String
    var selected: Bool
    var action: () -> Void
    var body: some View {
        Button { Haptics.selection(); action() } label: {
            // One line, never squeezed: a chip that wrapped cut « Général » in two.
            Text(title).scaledFont(14, .medium).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(selected ? Palette.background : Palette.foreground)
                .padding(.horizontal, 14).frame(minHeight: 36)
                .background(Capsule().fill(selected ? Palette.foreground : Palette.fill1))
                .overlay(Capsule().strokeBorder(selected ? .clear : Palette.glassBorder, lineWidth: 1))
                .hitTarget()
        }.buttonStyle(PressStyle(scale: 0.95))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SectionKicker: View {
    var text: String
    var color: Color = Palette.tertiary
    var body: some View {
        Text(text.uppercased()).scaledFont(12, .bold).tracking(1.8).foregroundStyle(color)
    }
}

struct AvatarView: View {
    var name: String
    var colorIndex: Int
    var size: CGFloat
    var body: some View {
        Text(String(name.trimmingCharacters(in: .whitespaces).first ?? "?").uppercased())
            .font(.system(size: size * 0.43, weight: .bold))
            .foregroundStyle(Palette.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(Palette.avatar(colorIndex)))
            .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .clear], startPoint: .top, endPoint: .center), lineWidth: 1.5))
            .accessibilityHidden(true)
    }
}

// MARK: - Animated word (vowels slide in and out)

/// Sizes its single child to a fraction of its ideal width so a letter can collapse to nothing.
struct CollapseLayout: Layout {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(.unspecified)
        return CGSize(width: size.width * progress, height: size.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: ProposedViewSize(child.sizeThatFits(.unspecified)))
    }
}

/// The prototype's wordmark: consonants stay, vowels appear in gold then vanish again.
/// The cycle starts when the word appears, so the vowels always arrive in view.
/// `once`: the vowels slide in a single time and stay (opening screen).
struct VowelWord: View {
    var word: String
    var font: Font
    var delay: Double = 0
    var once = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = Date()
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || RuntimeFlags.isTesting)) { context in
            let time = context.date.timeIntervalSince(appeared)
            HStack(spacing: 0) {
                ForEach(Array(word.enumerated()), id: \.offset) { index, character in
                    if Vowels.contains(character) {
                        let start = time - delay - Double(index) * (once ? Self.introStagger : 0.12)
                        let progress = reduceMotion || RuntimeFlags.isTesting ? 1 : (once ? Self.intro(start) : Self.progress(start))
                        CollapseLayout(progress: progress) { Text(String(character)).foregroundStyle(Palette.accent) }
                            .opacity(progress).clipped()
                    } else {
                        Text(String(character))
                    }
                }
            }.font(font).lineLimit(1).fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(word.capitalized)
    }
    /// Opening screen: each vowel slides in quickly, one after the other, and stays.
    static let introStagger = 0.07
    static func intro(_ time: Double) -> CGFloat {
        let t = min(max((time - 0.2) / 0.35, 0), 1)
        return CGFloat(t * t * (3 - 2 * t))
    }
    /// Opening screen length: the last vowel of `word` has settled, plus a short pause to read it.
    static func introDuration(_ word: String) -> Double {
        let last = Array(word).lastIndex(where: Vowels.contains) ?? 0
        return 0.2 + Double(last) * introStagger + 0.35 + 0.45
    }
    /// Same keyframes as the prototype's `vowelIn` (5 s cycle).
    static func progress(_ time: Double) -> CGFloat {
        let phase = (time.truncatingRemainder(dividingBy: 5) + 5).truncatingRemainder(dividingBy: 5) / 5
        func smooth(_ x: Double) -> CGFloat { let t = min(max(x, 0), 1); return CGFloat(t * t * (3 - 2 * t)) }
        switch phase {
        case ..<0.22: return 0
        case ..<0.38: return smooth((phase - 0.22) / 0.16)
        case ..<0.82: return 1
        default: return 1 - smooth((phase - 0.82) / 0.18)
        }
    }
}

/// A word with vowels highlighted in gold. One single Text, so when it shrinks to fit,
/// every letter shrinks by the same amount.
struct HighlightedWord: View {
    var word: String
    var font: Font
    var body: some View {
        var styled = AttributedString()
        for character in word {
            var letter = AttributedString(String(character))
            letter.foregroundColor = Vowels.contains(character) ? Palette.accent : Palette.foreground
            styled += letter
        }
        return Text(styled).font(font).lineLimit(1).minimumScaleFactor(0.5)
            .accessibilityLabel(word)
    }
}

struct Toast: View {
    var text: String
    var body: some View {
        Text(text).scaledFont(14, .semibold).foregroundStyle(Palette.foreground)
            .padding(.horizontal, 18).frame(minHeight: 40)
            .background(Capsule().fill(.ultraThinMaterial).overlay(Capsule().fill(LinearGradient(colors: [Palette.sheetTop, Palette.sheetBottom], startPoint: .top, endPoint: .bottom))))
            .overlay(Capsule().strokeBorder(Palette.glassBorder, lineWidth: 1))
            .shadow(color: Palette.glassShadow, radius: 15, y: 10)
    }
}

enum Format {
    /// 1:05, then 1:02:05 past an hour (a daily word opened the night before and found the next evening).
    static func clock(_ ms: Int) -> String {
        let total = max(0, ms / 1000)
        if total >= 3600 { return "\(total / 3600):" + String(format: "%02d:%02d", total % 3600 / 60, total % 60) }
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
    static func number(_ value: Int) -> String {
        value.formatted(.number.locale(Locale(identifier: "fr_FR")))
    }
    /// 1er, 2e, 3e…
    static func ordinal(_ value: Int) -> String { value == 1 ? "1er" : "\(number(value))e" }
    static func seconds(_ ms: Int?) -> String { ms.map { String(format: "%.1f s", Double($0) / 1000) } ?? "—" }
    /// "Mardi 21 octobre" for a yyyy-MM-dd key.
    static func day(_ key: String) -> String {
        let text = dayText(key, "EEEE d MMMM")
        return text.prefix(1).uppercased() + text.dropFirst()
    }
    /// "mardi" for a yyyy-MM-dd key.
    static func weekday(_ key: String) -> String { dayText(key, "EEEE") }
    private static func dayText(_ key: String, _ pattern: String) -> String {
        let utc = TimeZone(identifier: "UTC")
        let parser = DateFormatter(); parser.dateFormat = "yyyy-MM-dd"; parser.timeZone = utc; parser.locale = Locale(identifier: "en_US_POSIX")
        guard let date = parser.date(from: key) else { return key }
        let format = DateFormatter(); format.locale = Locale(identifier: "fr_FR"); format.timeZone = utc; format.dateFormat = pattern
        return format.string(from: date)
    }
    /// The week's words found out of its days so far: "5/7 jours", "1/3 jour".
    static func weekDays(_ week: DailyScore.Week, on day: String = DailySchedule.key()) -> String {
        "\(week.found)/\(DailyScore.dayOfWeek(day)) " + (week.found > 1 ? "jours" : "jour")
    }
}
