import SwiftUI
import StoreKit
import CNSNNCore

struct RootView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The opening wordmark stays until its vowels have slid in, then gives way to the app.
    @State private var introDone = RuntimeFlags.isTesting
    @AppStorage(AdMeasurement.key) private var adAnswer: Bool?
    var body: some View {
        ZStack {
            AmbientBackground()
            if !introDone || state.isRestoring { LaunchView(loading: introDone).transition(.opacity) }
            else if !state.progress.username.isEmpty { MainShell().transition(.opacity) }
            else {
                OnboardingView().readableWidth().transition(.opacity)
                    // New players only, once: may CNSNN's ads be measured (Google Ads)? Nothing is sent before "Oui".
                    .alert("Aider CNSNN à se faire connaître ?", isPresented: Binding(get: { adAnswer == nil && AdMeasurement.shouldAsk }, set: { _ in })) {
                        Button("Oui, d’accord") { AdMeasurement.set(true) }
                        Button("Non merci", role: .cancel) { AdMeasurement.set(false) }
                    } message: { Text(AdMeasurement.question) }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: introDone)
        .animation(CNSNNTheme.ease, value: state.progress.username.isEmpty)
        .animation(CNSNNTheme.ease, value: state.isRestoring)
        .task {
            state.finishInterruptedSprint()
            guard !introDone else { return }
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.8 : VowelWord.introDuration(LaunchView.word)))
            introDone = true
        }
        // Players from before the community rules accept them once (and again when they change).
        .sheet(isPresented: Binding(get: { introDone && !state.isRestoring && state.needsRulesAcceptance }, set: { _ in })) {
            CommunityRulesView(accepting: true)
        }
        .alert("CNSNN", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
            Button("Compris", role: .cancel) { state.error = nil }
        } message: { Text(state.error ?? "") }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case play = "Jouer", stats = "Stats", friends = "Amis", profile = "Profil"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .play: "suit.diamond.fill"
        case .stats: "chart.bar.fill"
        case .friends: "person.2.fill"
        case .profile: "person.fill"
        }
    }
}

struct GameRoute: Identifiable {
    let id = UUID()
    var mode: GameMode
    var category: CNSNNCore.Category? = nil
    var difficulty: Difficulty? = nil
    /// Sprint, Survie or Double sens instead of a daily or Classique game.
    var play: PlayMode? = nil
    /// A friend challenge.
    var challenge: Challenge? = nil
    /// A live duel: random opponent, link for a friend, or a friend's code.
    var live: LiveDuelSession.Start? = nil
    /// The weekly tournament's screen.
    var tournament = false
    /// Rattrapage: a missed daily word of the week, counted with 5 minutes more.
    var catchUpDay: String? = nil
    /// The first-launch tutorial on the Mot du jour page, with an example word.
    var tutorial = false
}

struct MainShell: View {
    @Environment(AppState.self) private var state
    @State private var tab: AppTab = .play
    @State private var game: GameRoute?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.requestReview) private var requestReview
    @AppStorage(Tutorial.seenKey) private var tutorialSeen = false
    @State private var showTutorial = false
    /// "À vous de jouer" at the end of the tutorial: the real daily game opens once it has closed.
    @State private var dailyAfterTutorial = false
    @State private var askReminder = false
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
        // The first-launch tutorial, above the tab bar, pointing at the daily card.
        .overlayPreferenceValue(TutorialAnchors.self) { anchors in
            if showTutorial {
                TutorialOverlay(anchors: anchors, play: {
                    showTutorial = false
                    game = GameRoute(mode: .daily, tutorial: true)
                }, skip: { tutorialSeen = true; showTutorial = false })
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : CNSNNTheme.ease, value: tab)
        .animation(CNSNNTheme.ease, value: showTutorial)
        .task {
            guard Tutorial.shouldShow(seen: tutorialSeen, state) else { return }
            try? await Task.sleep(for: .seconds(0.6))
            tab = .play
            showTutorial = true
        }
        .onChange(of: state.tutorialRequest) { _, _ in tab = .play; showTutorial = true }
        .onChange(of: state.leaderboardRequest) { _, _ in tab = .stats }
        .alert("Un rappel à 12h ?", isPresented: $askReminder) {
            Button("Oui, me le rappeler") { Task { await turnOnReminder() } }
            Button("Non merci", role: .cancel) {}
        } message: {
            Text("Chaque jour à midi : « N’oubliez pas le mot du jour », sauf si vous l’avez déjà joué. Vous pourrez changer l’heure dans Profil.")
        }
        // "Proposer un mot" on the daily result: the form lives in Profil.
        .onChange(of: state.proposeRequest) { _, _ in tab = .profile }
        .onChange(of: state.renameRequest) { _, _ in tab = .profile }
        .onChange(of: state.inviteCode) { _, code in if code != nil { tab = .play } }
        // A friend link: added once there is an account, then said in an alert.
        .task(id: (state.friendInviteCode ?? "") + "|" + (state.uid ?? "")) { await state.acceptFriendInvite() }
        .alert(state.friendInviteResult ?? "", isPresented: Binding(
            get: { state.friendInviteResult != nil }, set: { if !$0 { state.friendInviteResult = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .fullScreenCover(item: $game, onDismiss: afterGame) { route in
            if let challenge = route.challenge { ChallengeGameView(challenge: challenge) }
            else if let live = route.live { LiveDuelView(start: live) }
            else if route.tournament { TournamentView() }
            else if let play = route.play { ModeGameView(mode: play) }
            else if route.tutorial {
                GameView(mode: .daily, tutorial: { play in
                    tutorialSeen = true; dailyAfterTutorial = play; game = nil
                })
            }
            else { GameView(mode: route.mode, category: route.category, difficulty: route.difficulty, catchUpDay: route.catchUpDay) }
        }
    }
    @ViewBuilder private func content(_ page: AppTab) -> some View {
        Group {
            switch page {
            case .play: HomeView { game = $0 }
            case .stats: StatsView()
            case .friends: FriendsView { game = $0 }
            case .profile: ProfileView()
            }
        }.readableWidth()
    }
    /// Back on the home page after a found daily word: the reminder first (once), else the rating prompt.
    private func afterGame() {
        if dailyAfterTutorial {
            dailyAfterTutorial = false
            Task { try? await Task.sleep(for: .seconds(0.3)); game = GameRoute(mode: .daily) }
            return
        }
        if state.reminderPending { offerReminder() } else { askReviewIfPending() }
    }
    private func offerReminder() {
        state.reminderPending = false
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            switch await ReminderOffer.start() {
            case .systemPrompt: await turnOnReminder()
            case .askInApp: askReminder = true
            case .unavailable: break
            }
        }
    }
    private func turnOnReminder() async {
        Reminders.minutes = Reminders.defaultMinutes
        guard await Reminders.enable() else { return }
        state.remindersVersion += 1
        state.refreshGlance(force: true)
    }
    /// Apple's rating prompt, back on the home page after a found daily word, never during a game.
    private func askReviewIfPending() {
        guard state.reviewPending else { return }
        state.reviewPending = false
        ReviewPrompt.markAsked()
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            requestReview()
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
                        Text(item.rawValue).font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(selected ? Palette.foreground : Palette.tertiary)
                    .frame(width: 80, height: 56)
                    .background(Capsule().fill(selected ? Palette.tabOn : .clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle(scale: 0.94))
                .accessibilityLabel(item.rawValue)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityShowsLargeContentViewer()
            }
        }
        .padding(6)
        .modifier(TabBarGlass())
    }
}

/// The floating bar uses the system's Liquid Glass on iOS 26 and later, the prototype's frosted capsule before.
private struct TabBarGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular.interactive(), in: Capsule())
                .shadow(color: Palette.glassShadow, radius: 20, y: 16)
        } else {
            content
                .background(Capsule().fill(reduceTransparency ? AnyShapeStyle(Palette.surface) : AnyShapeStyle(.ultraThinMaterial)).overlay(Capsule().fill(LinearGradient(colors: [Palette.glassTop, Palette.glassBottom], startPoint: .top, endPoint: .bottom))))
                .overlay(Capsule().strokeBorder(LinearGradient(colors: [Palette.glassHighlight, Palette.glassBorder], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .shadow(color: Palette.glassShadow, radius: 20, y: 16)
        }
    }
}

/// Bottom padding so scrolling content clears the floating tab bar.
extension View {
    func tabBarInset() -> some View { safeAreaPadding(.bottom, 96) }
}

/// Opening screen: the vowels of CONSONNE slide in once. It stays while a returning
/// player's account is restored, instead of flashing the rules.
struct LaunchView: View {
    static let word = "CONSONNE"
    var loading: Bool
    var body: some View {
        VStack(spacing: 24) {
            VowelWord(word: Self.word, font: Typo.wordmark(50), once: true)
            ProgressView().tint(Palette.secondary).opacity(loading ? 1 : 0)
        }.accessibilityElement(children: .combine).accessibilityLabel(loading ? "Chargement de votre profil" : "CNSNN")
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var signingIn = false
    /// One screen, no question: the rules of the game, then straight in under an automatic pseudo
    /// ("Joueur4821"), changed in Profil whenever the player likes.
    var body: some View {
        VStack(spacing: 0) {
            // The whole page fits without scrolling: roomy on a big screen, tighter on a small
            // phone (iPhone SE) or a short iPad window, and only scrolls when nothing else fits
            // (very large text).
            ViewThatFits(in: .vertical) {
                welcome(compact: false)
                welcome(compact: true)
                ScrollView { welcome(compact: true) }.scrollBounceBehavior(.basedOnSize)
            }.frame(maxHeight: .infinity, alignment: sizeClass == .regular ? .center : .top)
            VStack(spacing: 4) {
                Button(state.isBusy ? "Un instant…" : "C’est parti", action: start)
                    .buttonStyle(PrimaryPillStyle())
                    .disabled(state.isBusy)
                Button("J’ai déjà un compte") { signingIn = true }
                    .scaledFont(15, .semibold).foregroundStyle(Palette.foreground)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("existing-account")
            }.padding(.horizontal, 26).padding(.top, 12).padding(.bottom, 8)
        }
        .sheet(isPresented: $signingIn) { SignInSheet() }
    }

    private func welcome(compact: Bool) -> some View {
        VStack(spacing: 0) {
            VowelWord(word: "CONSONNE", font: Typo.wordmark(compact ? 44 : 52))
                .padding(.top, compact ? 14 : 50)
            Text("Retrouvez le mot. Sans ses voyelles.")
                .font(Typo.serifItalic(compact ? 20 : 22)).foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center).padding(.top, compact ? 8 : 14)
            VStack(spacing: 0) {
                SectionKicker(text: "Exemple").frame(maxWidth: .infinity, alignment: .leading)
                Text("SRR").font(Typo.serif(compact ? 52 : 64)).tracking(3).padding(.top, compact ? 6 : 12)
                Text("Indice : « On le voit sur mon visage. »").scaledFont(15).foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center).padding(.top, compact ? 8 : 14)
                Rectangle().fill(Palette.line).frame(height: 1).padding(.vertical, compact ? 12 : 18)
                VowelWord(word: "SOURIRE", font: .system(size: compact ? 26 : 30, weight: .heavy), delay: 0.6).tracking(2.4)
            }.glassCard(radius: 30, padding: compact ? 16 : 22).padding(.top, compact ? 20 : 38)
            VStack(alignment: .leading, spacing: compact ? 10 : 14) {
                bullet("Tapez le mot complet, les accents sont ignorés")
                bullet("Un chrono tourne. Si vous séchez : les voyelles du mot s’allument, puis une phrase (30 s chacun)")
                bullet("Un mot du jour commun, et le mode Classique sans limite")
            }.padding(.horizontal, 6).padding(.top, compact ? 18 : 28)
        }.padding(.horizontal, 26)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Circle().fill(Palette.tertiary).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text(text).scaledFont(15).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func start() {
        guard !state.isBusy else { return }
        Haptics.success()
        Task { await state.start() }
    }
}

/// Signs in to an existing account from the first launch, so a returning player (new phone,
/// reinstall) finds their profile instead of creating a second one.
struct SignInSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message: String?
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        NavigationStack {
            Form {
                if state.cloud == nil {
                    Section { Text("Le serveur est injoignable pour le moment. Réessayez une fois connecté à Internet.") }
                } else {
                    Section {
                        TextField("Email", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Mot de passe", text: $password).textContentType(.password)
                        Button("Se connecter") { signIn() }.disabled(busy || trimmedEmail.isEmpty || password.isEmpty)
                        Button("Mot de passe oublié ?") { resetPassword() }.disabled(busy || trimmedEmail.isEmpty)
                    } footer: {
                        Text("Retrouvez votre pseudo, vos stats et votre série, comme sur votre ancien téléphone.")
                    }
                }
                if let message { Section { Text(message).foregroundStyle(.secondary) } }
            }
            .navigationTitle("J’ai déjà un compte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
    }
    private func signIn() {
        run {
            try await state.signIn(email: trimmedEmail, password: password)
            Haptics.success()
            dismiss()
        }
    }
    private func resetPassword() {
        run {
            try await state.cloud?.resetPassword(email: trimmedEmail)
            message = "Si cette adresse correspond à un compte, vous recevrez un lien pour choisir un nouveau mot de passe."
        }
    }
    private func run(_ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true; message = nil
        Task {
            defer { busy = false }
            do { try await work() } catch { message = CloudError.message(error) }
        }
    }
}

struct AvatarPicker: View {
    @Binding var selection: Int
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Palette.avatars.indices, id: \.self) { index in
                Button { Haptics.selection(); selection = index } label: {
                    Circle().fill(Palette.avatars[index]).frame(width: 32, height: 32)
                        .overlay(Circle().strokeBorder(Palette.foreground, lineWidth: selection == index ? 3 : 0).padding(-4))
                        .hitTarget()
                }
                .buttonStyle(PressStyle(scale: 0.9))
                .accessibilityLabel("Couleur \(index + 1)")
                .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }.padding(4)
    }
}
