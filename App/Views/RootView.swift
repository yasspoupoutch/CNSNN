import SwiftUI
import CNSNNCore

struct RootView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        ZStack {
            AmbientBackground()
            if !state.progress.username.isEmpty { MainShell().transition(.opacity) }
            else if state.isRestoring { LaunchView().transition(.opacity) }
            else { OnboardingView().transition(.opacity) }
        }
        .animation(CNSNNTheme.ease, value: state.progress.username.isEmpty)
        .animation(CNSNNTheme.ease, value: state.isRestoring)
        .alert("CNSNN", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
            Button("Compris", role: .cancel) { state.error = nil }
        } message: { Text(state.error ?? "") }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case play = "Jouer", stats = "Stats", propose = "Proposer", profile = "Profil"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .play: "suit.diamond.fill"
        case .stats: "chart.bar.fill"
        case .propose: "plus"
        case .profile: "person.fill"
        }
    }
}

struct GameRoute: Identifiable {
    let id = UUID()
    var mode: GameMode
    var category: CNSNNCore.Category? = nil
    var difficulty: Difficulty? = nil
}

struct MainShell: View {
    @State private var tab: AppTab = .play
    @State private var game: GameRoute?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack(alignment: .bottom) {
            // Every page stays alive so it keeps its state, as with a native tab view.
            ForEach(AppTab.allCases) { page in
                content(page)
                    .opacity(tab == page ? 1 : 0)
                    .offset(y: tab == page || reduceMotion ? 0 : 14)
                    .allowsHitTesting(tab == page)
                    .accessibilityHidden(tab != page)
            }
            TabPill(selection: $tab)
                .padding(.bottom, 8)
                .ignoresSafeArea(.keyboard)
        }
        .animation(reduceMotion ? nil : CNSNNTheme.ease, value: tab)
        .fullScreenCover(item: $game) { route in
            GameView(mode: route.mode, category: route.category, difficulty: route.difficulty)
        }
    }
    @ViewBuilder private func content(_ page: AppTab) -> some View {
        switch page {
        case .play: HomeView { game = $0 }
        case .stats: StatsView()
        case .propose: ProposeView()
        case .profile: ProfileView()
        }
    }
}

/// Floating liquid-glass tab bar from the prototype.
struct TabPill: View {
    @Binding var selection: AppTab
    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { item in
                let selected = selection == item
                Button {
                    if !selected { Haptics.selection() }
                    selection = item
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: item.symbol).font(.system(size: 17, weight: .bold)).frame(height: 20)
                        Text(item.rawValue).font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(selected ? Palette.foreground : Palette.tertiary)
                    .frame(width: 80, height: 56)
                    .background(Capsule().fill(selected ? Palette.tabOn : .clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle(scale: 0.94))
                .accessibilityLabel(item.rawValue)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(6)
        .background(Capsule().fill(.ultraThinMaterial).overlay(Capsule().fill(LinearGradient(colors: [Palette.glassTop, Palette.glassBottom], startPoint: .top, endPoint: .bottom))))
        .overlay(Capsule().strokeBorder(LinearGradient(colors: [Palette.glassHighlight, Palette.glassBorder], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .shadow(color: Palette.glassShadow, radius: 20, y: 16)
    }
}

/// Bottom padding so scrolling content clears the floating tab bar.
extension View {
    func tabBarInset() -> some View { safeAreaPadding(.bottom, 96) }
}

/// Shown while a returning player's account is restored, instead of flashing the rules.
struct LaunchView: View {
    var body: some View {
        VStack(spacing: 24) {
            VowelWord(word: "CONSONNE", font: .system(size: 50, weight: .heavy))
            ProgressView().tint(Palette.secondary)
        }.accessibilityElement(children: .combine).accessibilityLabel("Chargement de votre profil")
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @Environment(AppState.self) private var state
    @AppStorage(CNSNNTheme.avatarKey) private var avatar = 0
    @State private var step = 0
    @State private var username = ""
    @FocusState private var fieldFocused: Bool
    private var trimmed: String { username.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool { (2...20).contains(trimmed.count) }
    var body: some View {
        ZStack {
            if step == 0 { rules.transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)).combined(with: .opacity)) }
            else { pseudo.transition(.move(edge: .trailing).combined(with: .opacity)) }
        }.animation(CNSNNTheme.ease, value: step)
    }

    private var rules: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    VowelWord(word: "CONSONNE", font: .system(size: 50, weight: .heavy))
                        .padding(.top, 50)
                    Text("Retrouvez le mot. Sans ses voyelles.")
                        .font(Typo.serifItalic(22)).foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center).padding(.top, 14)
                    VStack(spacing: 0) {
                        SectionKicker(text: "Exemple").frame(maxWidth: .infinity, alignment: .leading)
                        Text("SRR").font(Typo.serif(64)).tracking(3).padding(.top, 12)
                        Text("Indice : « On le voit sur mon visage. »").font(.system(size: 15)).foregroundStyle(Palette.secondary)
                            .multilineTextAlignment(.center).padding(.top, 14)
                        Rectangle().fill(Palette.line).frame(height: 1).padding(.vertical, 18)
                        VowelWord(word: "SOURIRE", font: .system(size: 30, weight: .heavy), delay: 0.6).tracking(2.4)
                    }.glassCard(radius: 30, padding: 22).padding(.top, 38)
                    VStack(alignment: .leading, spacing: 14) {
                        bullet("Tapez le mot complet, les accents sont ignorés")
                        bullet("Un chrono tourne. Un indice si vous séchez, contre la moitié des points")
                        bullet("Un mot du jour commun, et le mode Classique sans limite")
                    }.padding(.horizontal, 6).padding(.top, 28)
                }.padding(.horizontal, 26)
            }.scrollBounceBehavior(.basedOnSize)
            Button("Continuer") { Haptics.selection(); step = 1 }
                .buttonStyle(PrimaryPillStyle())
                .padding(.horizontal, 26).padding(.bottom, 12)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Circle().fill(Palette.accent).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text(text).font(.system(size: 15)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pseudo: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CircleIconButton(symbol: "chevron.left", label: "Retour") { fieldFocused = false; step = 0 }
                    Text("Choisissez un pseudo").font(.system(size: 34, weight: .bold)).tracking(-0.6).padding(.top, 22)
                    Text("Pas d’inscription, pas d’email. Juste un nom pour jouer.")
                        .font(.system(size: 16)).foregroundStyle(Palette.secondary).padding(.top, 8)
                    AvatarView(name: trimmed.isEmpty ? "?" : trimmed, colorIndex: avatar, size: 104)
                        .shadow(color: Palette.glassShadow, radius: 20, y: 16)
                        .frame(maxWidth: .infinity).padding(.top, 34)
                    AvatarPicker(selection: $avatar).frame(maxWidth: .infinity).padding(.top, 20)
                    TextField("", text: $username, prompt: Text("ex. voyelle_hunter").foregroundStyle(Palette.tertiary))
                        .font(.system(size: 19, weight: .medium)).foregroundStyle(Palette.foreground)
                        .textContentType(.nickname).autocorrectionDisabled().textInputAutocapitalization(.never)
                        .submitLabel(.go).onSubmit(start)
                        .focused($fieldFocused)
                        .padding(.horizontal, 20).frame(height: 58)
                        .glassPanel(radius: 20, padding: 0)
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(fieldFocused ? Palette.accent : .clear, lineWidth: 1))
                        .padding(.top, 30)
                        .accessibilityLabel("Pseudo, entre 2 et 20 caractères")
                    Text(message.text).font(.system(size: 13)).foregroundStyle(message.color)
                        .frame(minHeight: 20).padding(.horizontal, 4).padding(.top, 10)
                }.padding(.horizontal, 26).padding(.top, 10)
            }.scrollDismissesKeyboard(.interactively).scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 12) {
                Button(state.isBusy ? "Un instant…" : "C’est parti", action: start)
                    .buttonStyle(PrimaryPillStyle())
                    .disabled(state.isBusy || !valid)
                Text("Modifiable à tout moment depuis votre profil.").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            }.padding(.horizontal, 26).padding(.bottom, 12)
        }
    }

    private var message: (text: String, color: Color) {
        if trimmed.isEmpty { return ("", Palette.tertiary) }
        return valid ? ("✓ Parfait", Palette.mint) : ("Entre 2 et 20 caractères", Palette.tertiary)
    }

    private func start() {
        guard valid, !state.isBusy else { return }
        fieldFocused = false
        Haptics.success()
        Task { await state.start(username: username) }
    }
}

struct AvatarPicker: View {
    @Binding var selection: Int
    var body: some View {
        HStack(spacing: 12) {
            ForEach(Palette.avatars.indices, id: \.self) { index in
                Button { Haptics.selection(); selection = index } label: {
                    Circle().fill(Palette.avatars[index]).frame(width: 32, height: 32)
                        .overlay(Circle().strokeBorder(Palette.foreground, lineWidth: selection == index ? 3 : 0).padding(-4))
                }
                .buttonStyle(PressStyle(scale: 0.9))
                .accessibilityLabel("Couleur \(index + 1)")
                .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }.padding(4)
    }
}
