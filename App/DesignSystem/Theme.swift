import SwiftUI
import UIKit

enum CNSNNTheme {
    static let background = Color(red: 0.025, green: 0.029, blue: 0.035)
    static let surface = Color(red: 0.085, green: 0.094, blue: 0.108)
    static let accent = Color(red: 0.82, green: 0.89, blue: 0.77)
    static let radius: CGFloat = 30
    static let spacing: CGFloat = 20
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.84)
}
enum Haptics {
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func retry() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
}
struct NativeGlass: ViewModifier {
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(CNSNNTheme.surface, in: Capsule())
        } else if #available(iOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: .capsule)
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 0.5))
        }
    }
}
extension View {
    func cnsnnGlass(interactive: Bool = false) -> some View { modifier(NativeGlass(interactive: interactive)) }
    func cnsnnSurface() -> some View {
        padding(24).background(CNSNNTheme.surface, in: RoundedRectangle(cornerRadius: CNSNNTheme.radius))
            .overlay(RoundedRectangle(cornerRadius: CNSNNTheme.radius).stroke(.white.opacity(0.07), lineWidth: 1))
    }
}
struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : CNSNNTheme.spring, value: configuration.isPressed)
    }
}
struct CNSNNButton: View {
    var title: String
    var symbol: String = "arrow.right"
    var action: () -> Void
    var body: some View {
        Button { Haptics.selection(); action() } label: {
            HStack { Text(title).font(.headline); Spacer(); Image(systemName: symbol) }
                .padding(.horizontal, 22).padding(.vertical, 18)
                .foregroundStyle(CNSNNTheme.background)
                .background(CNSNNTheme.accent, in: Capsule())
        }.buttonStyle(PressStyle())
    }
}
struct GlassCapsule: View {
    var text: String
    var symbol: String
    var body: some View {
        Label(text, systemImage: symbol).font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16).padding(.vertical, 12).cnsnnGlass()
    }
}
struct StatCard: View {
    var title: String
    var value: String
    var symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol).foregroundStyle(CNSNNTheme.accent).accessibilityHidden(true)
            Text(value).font(.system(.title, design: .rounded).weight(.semibold)).monospacedDigit()
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).cnsnnSurface()
            .accessibilityElement(children: .combine)
    }
}
struct AnswerField: View {
    @Binding var answer: String
    var submit: () -> Void
    var body: some View {
        TextField("Ton mot…", text: $answer).font(.title3.weight(.medium))
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .submitLabel(.go).onSubmit(submit)
            .padding(20).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
            .accessibilityLabel("Réponse au mot")
    }
}

struct CNSNNGlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(iOS 26.0, *) { GlassEffectContainer(spacing: 16) { content() } }
        else { content() }
    }
}
struct CardTransition: ViewModifier {
    var id: String
    var namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), !reduceMotion { content.navigationTransition(.zoom(sourceID: id, in: namespace)) }
        else { content }
    }
}
struct CardTransitionSource: ViewModifier {
    var id: String
    var namespace: Namespace.ID
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) { content.matchedTransitionSource(id: id, in: namespace) }
        else { content }
    }
}
