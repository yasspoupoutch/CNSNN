import SwiftUI
import CNSNNCore

// Défi entre amis: the purple tile on the home page, the sheet to challenge a friend, the game and its result.

extension Palette {
    /// The challenge's lilac: only on challenge surfaces, so it never competes with the gold vowels.
    static let duel = Color(red: 0.788, green: 0.655, blue: 1.0)
    static let duelText = Color(red: 0.902, green: 0.847, blue: 1.0)
    static let duelSoft = Color(red: 0.851, green: 0.784, blue: 1.0)
}

enum ChallengeClock {
    static var nowMs: Int { Int(Date().timeIntervalSince1970 * 1000) }
}

/// Lilac glass: the tile and the cards of the challenge.
struct DuelSurface: ViewModifier {
    var radius: CGFloat = 26
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(LinearGradient(colors: [Palette.duel.opacity(0.26), Color(red: 0.47, green: 0.35, blue: 0.86).opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(shape.strokeBorder(LinearGradient(colors: [Palette.duelText.opacity(0.6), Palette.duel.opacity(0.42)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}

struct DuelButtonStyle: ButtonStyle {
    var height: CGFloat = 44
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledFont(15, .semibold).foregroundStyle(Palette.duelText)
            .padding(.horizontal, 18).frame(minHeight: height)
            .background(Capsule().fill(Palette.duel.opacity(0.18)))
            .overlay(Capsule().strokeBorder(Palette.duel.opacity(0.45), lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(CNSNNTheme.spring, value: configuration.isPressed)
    }
}

private struct DuelGlyph: View {
    var size: CGFloat = 46
    var body: some View {
        Image(systemName: "figure.fencing").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(Palette.duelText)
            .frame(width: size, height: size)
            .background(Circle().fill(Palette.duel.opacity(0.22)))
            .overlay(Circle().strokeBorder(Palette.duel.opacity(0.5), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

func avatarIndex(_ uid: String) -> Int { uid.unicodeScalars.reduce(0) { $0 + Int($1.value) } }

// MARK: - Home tile

/// "Défier un ami", or the challenge that needs the player: a friend's to play, mine to finish,
/// or the one waiting for the friend.
struct ChallengeTile: View {
    @Environment(AppState.self) private var state
    var open: () -> Void
    var play: (Challenge) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let featured = state.featuredChallenge()
            Button {
                Haptics.selection()
                if let featured, featured.state != .waiting { play(featured.challenge) } else { open() }
            } label: {
                HStack(spacing: 14) {
                    if let featured, let uid = state.uid, !featured.challenge.isOpen {
                        let other = featured.challenge.theirs(uid)
                        AvatarView(name: other.name, colorIndex: avatarIndex(other.uid), size: 40)
                    } else {
                        DuelGlyph()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(featured)).scaledFont(17, .bold).foregroundStyle(Palette.foreground).lineLimit(1).minimumScaleFactor(0.8)
                        Text(subtitle(featured)).scaledFont(13).foregroundStyle(Palette.duelSoft).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    if let featured, featured.state != .waiting {
                        Text(featured.state == .playing ? "Reprendre" : "Jouer").scaledFont(15, .semibold).foregroundStyle(Palette.duelText)
                            .padding(.horizontal, 16).frame(minHeight: 40)
                            .background(Capsule().fill(Palette.duel.opacity(0.22)))
                            .overlay(Capsule().strokeBorder(Palette.duel.opacity(0.5), lineWidth: 1))
                    } else {
                        Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.tertiary)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(DuelSurface())
                .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            .buttonStyle(PressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title(featured) + ". " + subtitle(featured))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("challengeTile")
        }
    }

    private func title(_ featured: (challenge: Challenge, state: Challenge.State)?) -> String {
        guard let featured, let uid = state.uid else { return "Défier un ami" }
        let name = featured.challenge.theirs(uid).name
        switch featured.state {
        case .yourTurn: return "\(name) vous a défié !"
        case .playing: return featured.challenge.isOpen ? "Défi par lien en cours" : "Défi en cours contre \(name)"
        default: return featured.challenge.isOpen ? "Défi par lien en attente" : "En attente de \(name)"
        }
    }
    private func subtitle(_ featured: (challenge: Challenge, state: Challenge.State)?) -> String {
        guard let featured, let uid = state.uid else {
            let tally = state.challengeTally().label
            return "Mêmes 5 mots. Le plus rapide gagne." + (tally.map { "\n" + $0 } ?? "")
        }
        let c = featured.challenge, now = ChallengeClock.nowMs
        switch featured.state {
        case .yourTurn: return "Son chrono : caché · plus que " + ChallengeFormat.left(c.startDeadlineMs() - now)
        case .playing: return "Votre chrono tourne · 5 mots"
        default:
            let left = c.theirs(uid).startedMs == nil ? c.startDeadlineMs() : c.finishDeadlineMs()
            return "Votre chrono : " + ChallengeFormat.time(c.mine(uid).scoreMs ?? 0) + " · encore " + ChallengeFormat.left(left - now)
        }
    }
}

// MARK: - Sheet: challenge a friend

struct ChallengeSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    var play: (Challenge) -> Void
    @State private var friends: [(uid: String, name: String)] = []
    @State private var code: String?
    @State private var loading = true
    @State private var sending: String?
    @State private var message: String?
    @State private var joinCode = ""
    @FocusState private var joinFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    DuelGlyph(size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        SectionKicker(text: "Défi entre amis", color: Palette.duel)
                        Text("Mêmes 5 mots. Le plus rapide gagne.").scaledFont(19, .bold).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.top, 8)
                Text("Votre chrono démarre dès que vous lancez le défi. Votre ami a 48 h pour jouer ; chaque mot passé ajoute 20 s.")
                    .scaledFont(13).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                if let label = state.challengeTally().label {
                    Text("Votre bilan : " + label).scaledFont(14, .semibold).foregroundStyle(Palette.duelSoft)
                }
                if state.uid == nil {
                    Text("Connectez-vous à Internet pour défier vos amis.").scaledFont(15).foregroundStyle(Palette.secondary).glassPanel(radius: 22, padding: 16)
                } else {
                    openList
                    joinBox
                    friendList
                    linkBox
                    finishedList
                }
                if let message { Text(message).scaledFont(13).foregroundStyle(Palette.red) }
                invite
            }.padding(.horizontal, 22).padding(.vertical, 20)
        }
        .scrollIndicators(.hidden)
        .task(id: state.uid) { await load() }
        .onChange(of: state.inviteCode) { _, code in
            guard let code else { return }
            state.inviteCode = nil; joinCode = code; join()
        }
        .environment(\.colorScheme, .dark)
    }

    private var openChallenges: [Challenge] {
        guard let uid = state.uid else { return [] }
        let now = ChallengeClock.nowMs
        return state.challenges.filter { if case .over = $0.state(for: uid, now: now) { return false }; return true }
    }

    @ViewBuilder private var openList: some View {
        if let uid = state.uid, !openChallenges.isEmpty {
            SectionKicker(text: "En cours").padding(.top, 6)
            VStack(spacing: 0) {
                ForEach(Array(openChallenges.enumerated()), id: \.element.id) { index, c in
                    if index > 0 { Rectangle().fill(Palette.line).frame(height: 1) }
                    let other = c.theirs(uid), status = c.state(for: uid, now: ChallengeClock.nowMs)
                    HStack(spacing: 12) {
                        if c.isOpen { DuelGlyph(size: 34) } else { AvatarView(name: other.name, colorIndex: avatarIndex(other.uid), size: 34) }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.opponentName(uid)).scaledFont(15, .semibold).lineLimit(1)
                            Text(openLine(c, status: status, uid: uid)).scaledFont(12).foregroundStyle(Palette.tertiary).lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        if status == .yourTurn || status == .playing {
                            Button(status == .playing ? "Reprendre" : "Jouer") { start(c) }.buttonStyle(DuelButtonStyle(height: 38))
                        } else if c.isOpen, let code = c.code {
                            ShareLink(item: ChallengeInvite.shareText(code: code)) { Text("Partager") }.buttonStyle(DuelButtonStyle(height: 38))
                        }
                    }.padding(.horizontal, 14).frame(minHeight: 60)
                }
            }.glassPanel(radius: 22, padding: 0)
        }
    }

    private func openLine(_ c: Challenge, status: Challenge.State, uid: String) -> String {
        let now = ChallengeClock.nowMs
        switch status {
        case .yourTurn: return "Vous a défié · plus que " + ChallengeFormat.left(c.startDeadlineMs() - now)
        case .playing: return "Votre chrono tourne"
        default:
            if c.isOpen { return "Code " + (c.code ?? "") + " · personne n’a encore rejoint" }
            return "Votre chrono : " + ChallengeFormat.time(c.mine(uid).scoreMs ?? 0)
                + (c.theirs(uid).startedMs == nil ? " · pas encore joué" : " · en train de jouer")
        }
    }

    @ViewBuilder private var friendList: some View {
        SectionKicker(text: "Défier un ami").padding(.top, 6)
        VStack(spacing: 0) {
            if friends.isEmpty {
                HStack {
                    if loading { ProgressView().tint(Palette.secondary) }
                    Text(loading ? "Chargement…" : "Ajoutez d’abord un ami avec son code (Stats › Classement › Amis), ou invitez-le ci-dessous.")
                        .scaledFont(14).foregroundStyle(Palette.tertiary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            ForEach(Array(friends.enumerated()), id: \.element.uid) { index, friend in
                // The friend's current pseudo when known (the list keeps the one saved when added).
                let name = state.currentNames[friend.uid] ?? friend.name
                if index > 0 { Rectangle().fill(Palette.line).frame(height: 1) }
                HStack(spacing: 12) {
                    AvatarView(name: name, colorIndex: avatarIndex(friend.uid), size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).scaledFont(15, .semibold).lineLimit(1)
                        Text(state.challengeTally(friend: friend.uid).label ?? "Aucun défi pour l’instant")
                            .scaledFont(12).foregroundStyle(Palette.duelSoft.opacity(0.85)).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button {
                        send(friend)
                    } label: {
                        if sending == friend.uid { ProgressView().tint(Palette.duelText) } else { Text("Défier") }
                    }
                    .buttonStyle(DuelButtonStyle(height: 38)).disabled(sending != nil)
                    .accessibilityLabel("Défier \(name)")
                }.padding(.horizontal, 14).frame(minHeight: 60)
            }
        }.glassPanel(radius: 22, padding: 0)
    }

    /// A code received from a friend (or the link the app was opened with).
    private var joinBox: some View {
        HStack(spacing: 10) {
            TextField("", text: $joinCode, prompt: Text("Code d’un défi reçu").foregroundStyle(Palette.tertiary))
                .scaledFont(16, .semibold).textInputAutocapitalization(.characters).autocorrectionDisabled()
                .focused($joinFocused).submitLabel(.join).onSubmit { join() }
                .onChange(of: joinCode) { _, text in
                    let cleaned = String(text.uppercased().filter { ChallengeInvite.alphabet.contains($0) }.prefix(6))
                    if cleaned != text { joinCode = cleaned }
                }
                .accessibilityIdentifier("joinCode")
            Button { join() } label: {
                if sending == "join" { ProgressView().tint(Palette.duelText) } else { Text("Rejoindre") }
            }
            .buttonStyle(DuelButtonStyle(height: 38)).disabled(joinCode.count != 6 || sending != nil)
        }
        .padding(.leading, 16).padding(.trailing, 10).frame(minHeight: 60).glassPanel(radius: 22, padding: 0)
        .padding(.top, 6)
    }

    /// For someone who is not a friend yet: play first, then send the link with its code.
    private var linkBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pas encore amis ? Jouez d’abord, puis envoyez le lien. Le premier qui l’ouvre a 48 h pour vous battre.")
                .scaledFont(13).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            Button { sendOpen() } label: {
                if sending == "link" { ProgressView().tint(Palette.duelText) } else { Label("Défier par lien", systemImage: "link") }
            }
            .buttonStyle(DuelButtonStyle(height: 46)).frame(maxWidth: .infinity).disabled(sending != nil)
            .accessibilityIdentifier("openChallenge")
        }
        .padding(16).modifier(DuelSurface(radius: 22)).padding(.top, 6)
    }

    @ViewBuilder private var finishedList: some View {
        let done = finished
        if !done.isEmpty, let uid = state.uid {
            SectionKicker(text: "Derniers défis").padding(.top, 6)
            VStack(spacing: 0) {
                ForEach(Array(done.prefix(5).enumerated()), id: \.offset) { index, item in
                    if index > 0 { Rectangle().fill(Palette.line).frame(height: 1) }
                    let (c, result) = item
                    HStack {
                        Text(c.isOpen ? resultTitle(result) + " · défi par lien" : resultTitle(result) + " contre " + c.theirs(uid).name).scaledFont(14, .semibold)
                            .foregroundStyle(result == .won ? Palette.mint : result == .lost ? Palette.red : Palette.secondary).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(scoreLine(c, uid: uid)).scaledFont(13).monospacedDigit().foregroundStyle(Palette.tertiary)
                    }.padding(.horizontal, 14).frame(minHeight: 48)
                }
            }.glassPanel(radius: 22, padding: 0)
        }
    }

    private var finished: [(Challenge, Challenge.Result)] {
        guard let uid = state.uid else { return [] }
        let now = ChallengeClock.nowMs
        return state.challenges.compactMap { c in c.result(for: uid, now: now).map { (c, $0) } }
    }
    private func resultTitle(_ result: Challenge.Result) -> String {
        switch result { case .won: "Victoire"; case .lost: "Défaite"; case .draw: "Égalité"; case .expired: "Expiré" }
    }
    private func scoreLine(_ c: Challenge, uid: String) -> String {
        let mine = c.mine(uid).scoreMs.map(ChallengeFormat.time) ?? "—"
        let theirs = c.theirs(uid).scoreMs.map(ChallengeFormat.time) ?? "—"
        return mine + " / " + theirs
    }

    private var invite: some View {
        // A friend invite, not a challenge: it carries no challenge, only the friend code (challenges go by link).
        let text = "Ajoute-moi en ami sur CNSNN, le jeu de mots sans voyelles : on pourra se défier et comparer nos temps !"
            + (code.map { " Mon code ami : " + $0 + "." } ?? "") + " " + Site.appStore.absoluteString
        return ShareLink(item: text) {
            Label("Inviter par message", systemImage: "square.and.arrow.up").scaledFont(15, .semibold)
        }.buttonStyle(GlassPillStyle(height: 50)).padding(.top, 6)
    }

    private func load() async {
        guard let cloud = state.cloud, let uid = state.uid else { loading = false; return }
        defer { loading = false }
        if let invite = state.inviteCode { state.inviteCode = nil; joinCode = invite; join() }
        friends = (try? await cloud.friends(uid: uid)) ?? []
        loading = false
        await state.refreshChallenges()
        if code == nil { code = try? await cloud.friendCode(uid: uid, username: state.progress.username.isEmpty ? "Joueur" : state.progress.username) }
    }

    private func send(_ friend: (uid: String, name: String)) {
        guard sending == nil else { return }
        sending = friend.uid; message = nil
        Haptics.selection()
        Task {
            defer { sending = nil }
            do {
                let challenge = try await state.sendChallenge(to: friend.uid, name: friend.name)
                play(challenge)
                dismiss()
            } catch { message = CloudError.message(error); Haptics.retry() }
        }
    }

    private func join() {
        guard sending == nil, let code = ChallengeInvite.code(in: joinCode) else { return }
        sending = "join"; message = nil; joinFocused = false
        Haptics.selection()
        Task {
            defer { sending = nil }
            do {
                let challenge = try await state.joinChallenge(code: code)
                joinCode = ""
                play(challenge)
                dismiss()
            } catch { message = CloudError.message(error); Haptics.retry() }
        }
    }

    private func sendOpen() {
        guard sending == nil else { return }
        sending = "link"; message = nil
        Haptics.selection()
        Task {
            defer { sending = nil }
            do {
                let challenge = try await state.sendOpenChallenge()
                play(challenge)
                dismiss()
            } catch { message = CloudError.message(error); Haptics.retry() }
        }
    }

    private func start(_ challenge: Challenge) {
        play(challenge)
        dismiss()
    }
}

// MARK: - Result prompt after the daily word

struct ChallengePrompt: View {
    var correct: Bool
    var action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                DuelGlyph(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(correct ? "Vous êtes en forme !" : "Prenez votre revanche !").scaledFont(17, .bold)
                    Text("Défiez un ami sur 5 mots, le plus rapide gagne.").scaledFont(13).foregroundStyle(Palette.duelSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button("Défier un ami") { Haptics.selection(); action() }
                .buttonStyle(DuelButtonStyle(height: 48)).frame(maxWidth: .infinity)
                .accessibilityIdentifier("challengePrompt")
        }
        .padding(16).modifier(DuelSurface(radius: 26))
    }
}

// MARK: - The game

struct ChallengeGameView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session: ChallengeSession
    @State private var confirmQuit = false
    @State private var shakes: CGFloat = 0
    @State private var showPassed = false

    init(challenge: Challenge) { _session = State(initialValue: ChallengeSession(challenge: challenge)) }

    private var opponent: String { state.uid.map { session.challenge.opponentName($0) } ?? "" }

    var body: some View {
        ZStack {
            AmbientBackground(dimmed: session.phase == .playing)
            VStack(spacing: 0) {
                topBar
                switch session.phase {
                case .playing: if let game = session.game { board(game) }
                case .starting, .sending:
                    Spacer()
                    ProgressView().tint(Palette.secondary)
                    Text(session.phase == .starting ? "Lancement du chrono…" : "Envoi de votre temps…").scaledFont(14).foregroundStyle(Palette.secondary).padding(.top, 10)
                    Spacer()
                case .failed(let text):
                    Spacer()
                    Text(text).scaledFont(16).multilineTextAlignment(.center).foregroundStyle(Palette.secondary).padding(.horizontal, 20)
                    Button("Réessayer") { session.phase = .starting; Task { await session.begin(state: state) } }
                        .buttonStyle(GlassPillStyle(height: 50)).padding(.top, 20).padding(.horizontal, 40)
                    Spacer()
                case .done: Spacer()
                }
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 6).readableWidth()
            if session.phase == .done {
                Palette.dim.ignoresSafeArea().transition(.opacity)
                VStack {
                    Spacer()
                    ChallengeResultView(session: session, close: { dismiss() }).padding(.horizontal, 8)
                }.readableWidth().transition(.move(edge: .bottom))
            }
        }
        .animation(reduceMotion ? nil : CNSNNTheme.ease, value: session.phase)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .task { if session.phase == .starting { await session.begin(state: state) } }
        .onChange(of: session.mistakeTick) { _, _ in
            withAnimation(reduceMotion ? nil : .linear(duration: 0.42)) { shakes += 1 }
            AccessibilityNotification.Announcement("Ce n’est pas le mot").post()
        }
        .onChange(of: session.passedTick) { _, tick in
            guard let word = session.passed else { return }
            showPassed = true
            AccessibilityNotification.Announcement("C’était " + word).post()
            Task { try? await Task.sleep(for: .seconds(2)); if session.passedTick == tick { showPassed = false } }
        }
        .confirmationDialog("Quitter le défi ?", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("Reprendre plus tard") { dismiss() }
            Button("Abandonner", role: .destructive) { session.abandon(state: state) }
            Button("Continuer à jouer", role: .cancel) {}
        } message: { Text("Le chrono continue pendant votre absence. Abandonner compte les mots restants comme passés (+20 s chacun).") }
    }

    private var topBar: some View {
        HStack {
            CircleIconButton(symbol: "xmark", label: "Quitter") {
                if session.phase == .playing { confirmQuit = true } else { dismiss() }
            }
            Spacer()
            if session.phase == .playing {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let ms = session.game?.scoreMs(elapsed: session.elapsedMs) ?? 0
                    Text(ChallengeFormat.time(ms)).scaledFont(14, .bold).monospacedDigit()
                        .padding(.horizontal, 13).frame(minHeight: 36).glassCapsule()
                        .accessibilityLabel("Chrono : " + ChallengeFormat.time(ms))
                }
            }
        }
        .overlay {
            VStack(spacing: 1) {
                Text("Défi").scaledFont(16, .semibold)
                Text(session.challenge.isOpen ? opponent : "contre " + opponent).scaledFont(12).foregroundStyle(Palette.tertiary)
            }.lineLimit(1).accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
        }
        .frame(minHeight: 48)
    }

    @ViewBuilder private func board(_ game: ChallengeGame) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<game.cards.count, id: \.self) { index in
                Capsule().fill(index < game.index ? Palette.duel : index == game.index ? Palette.foreground : Palette.fill2)
                    .frame(height: 5)
            }
        }.padding(.top, 10).padding(.horizontal, 30)
            .accessibilityElement().accessibilityLabel("Mot \(min(game.index + 1, game.cards.count)) sur \(game.cards.count)")
        if let card = game.card { clue(card, number: game.index + 1) }
        // "C'était : …" over the free space for two seconds after a pass, so the board never moves.
        Spacer(minLength: 8).overlay {
            Text("C’était : " + (session.passed ?? "").uppercased())
                .scaledFont(14, .semibold).foregroundStyle(Palette.secondary).lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 14).frame(minHeight: 32).glassCapsule()
                .opacity(showPassed && session.passed != nil ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: showPassed)
                .accessibilityHidden(true)
        }
        answerLine
        Button { Haptics.selection(); session.skip(state: state) } label: {
            Text("Passer · +20 s").scaledFont(13, .medium).foregroundStyle(Palette.secondary)
                .padding(.horizontal, 16).frame(minHeight: 36).glassCapsule().hitTarget()
        }
        .buttonStyle(PressStyle()).accessibilityLabel("Passer ce mot, 20 secondes de pénalité").padding(.vertical, 10)
        LetterKeyboard(press: session.press, delete: session.delete, submit: { session.submit(state: state) })
    }

    private func clue(_ card: Card, number: Int) -> some View {
        VStack(spacing: 0) {
            Text("Mot \(number) sur \(ChallengeRules.words)").scaledFont(12).foregroundStyle(Palette.tertiary)
            let consonants = card.wordNoVowels
            Text(consonants)
                .font(Typo.serif(consonants.count > 5 ? 60 : 80)).tracking(3)
                .lineLimit(1).minimumScaleFactor(0.35).padding(.top, 6)
                .accessibilityLabel("Consonnes : " + WordEngine.spoken(consonants))
                .id(card.id)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .offset(y: 12).combined(with: .opacity), removal: .opacity))
            Text("\(card.category.rawValue) · \(card.difficulty.rawValue)").scaledFont(12).foregroundStyle(Palette.tertiary).padding(.top, 4)
            Text("« \(card.hint) »").font(Typo.serifItalic(22)).multilineTextAlignment(.center).lineSpacing(2)
                .lineLimit(3).minimumScaleFactor(0.7).padding(.horizontal, 10).padding(.top, 14)
                .id("hint-" + card.id)
        }
        .padding(.top, 18)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: card.id)
    }

    private var answerLine: some View {
        HStack(spacing: 2) {
            if session.answer.isEmpty {
                Text("votre réponse").font(Typo.serifItalic(22)).foregroundStyle(Palette.tertiary)
            }
            if !session.answer.isEmpty { AnswerLetters(answer: session.answer) }
            Caret()
        }
        .lineLimit(1).minimumScaleFactor(0.4)
        .frame(maxWidth: .infinity, minHeight: 52)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.tertiary).frame(height: 1) }
        .padding(.horizontal, 24)
        .modifier(Shake(animatableData: shakes))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Votre réponse")
        .accessibilityValue(session.answer.isEmpty ? "vide" : session.answer)
    }
}

private struct ChallengeResultView: View {
    @Environment(AppState.self) private var state
    var session: ChallengeSession
    var close: () -> Void

    var body: some View {
        let uid = state.uid ?? ""
        let c = session.challenge, me = c.mine(uid), other = c.theirs(uid)
        let result = c.result(for: uid, now: ChallengeClock.nowMs)
        let otherName = c.isOpen ? "Adversaire" : other.name
        VStack(spacing: 0) {
            Text(c.isOpen && result == nil ? "Défi prêt à partager" : kicker(result, other: other.name)).font(Typo.serifItalic(24))
                .foregroundStyle(result == .won ? Palette.mint : result == .lost ? Palette.red : Palette.duelSoft)
                .multilineTextAlignment(.center)
                // After a challenge, the natural moment to ask: "tell me when my friend has played".
                .task { await ChallengeWatch.requestPermission() }
            Text(ChallengeFormat.time(session.myScoreMs(uid: uid))).font(.system(size: 64, weight: .heavy)).tracking(-1.5).monospacedDigit()
                .padding(.top, 6)
                .accessibilityLabel("Votre temps : " + ChallengeFormat.time(session.myScoreMs(uid: uid)))
            Text(me.skips > 0 ? "votre temps, dont \(me.skips * 20) s de pénalité" : "votre temps").scaledFont(13).foregroundStyle(Palette.tertiary)
            HStack(spacing: 10) {
                tile(other.scoreMs.map(ChallengeFormat.time) ?? (result == nil ? "caché" : "—"), otherName)
                tile("\(ChallengeRules.words - me.skips)/\(ChallengeRules.words)", "mots trouvés")
                tile(Mistakes.text(me.errors), "réponses")
            }.padding(.top, 18)
            if let missed = session.game?.missed, !missed.isEmpty {
                Text((missed.count > 1 ? "Les réponses manquées : " : "La réponse manquée : ") + missed.map { "« \($0) »" }.joined(separator: ", ") + ".")
                    .scaledFont(13).foregroundStyle(Palette.tertiary).multilineTextAlignment(.center).padding(.top, 10)
            }
            Text(c.isOpen && result == nil ? "Envoyez le lien : le premier qui l’ouvre a 48 h pour battre votre temps, qui reste caché jusque-là." : footer(result, other: other)).scaledFont(13).foregroundStyle(Palette.secondary).multilineTextAlignment(.center).padding(.top, 14)
            HStack(spacing: 10) {
                if result == nil, c.isOpen, let code = c.code {
                    ShareLink(item: ChallengeInvite.shareText(code: code)) { Text("Envoyer le lien") }
                        .buttonStyle(GlassPillStyle(height: 54)).accessibilityIdentifier("shareChallengeLink")
                } else if result == nil {
                    ShareLink(item: "Je t’ai défié sur CNSNN : 5 mots, mon chrono est caché jusqu’à ce que tu joues. Ouvre l’app pour relever le défi ! " + Site.appStore.absoluteString) {
                        Text("Prévenir \(other.name)")
                    }.buttonStyle(GlassPillStyle(height: 54))
                }
                Button("Terminer", action: close).buttonStyle(PrimaryPillStyle(height: 54))
            }.padding(.top, 20)
            if !c.isOpen, let label = state.challengeTally(friend: other.uid).label {
                Text("Contre \(other.name) : " + label).scaledFont(12).foregroundStyle(Palette.tertiary).padding(.top, 12)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 26)
        .background {
            let shape = RoundedRectangle(cornerRadius: 48, style: .continuous)
            shape.fill(.ultraThinMaterial).overlay(shape.fill(LinearGradient(colors: [Palette.sheetTop, Palette.sheetBottom], startPoint: .top, endPoint: .bottom)))
                .overlay(shape.strokeBorder(LinearGradient(colors: [Palette.glassHighlight, Palette.glassBorder], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .shadow(color: Palette.glassShadow, radius: 30, y: -20)
        }
        .onAppear { if result == .won { Haptics.success() } }
    }

    private func kicker(_ result: Challenge.Result?, other: String) -> String {
        switch result {
        case .won?: "Victoire contre \(other) !"
        case .lost?: "\(other) a été plus rapide…"
        case .draw?: "Égalité parfaite !"
        case .expired?: "Défi expiré"
        case nil: "Défi envoyé à \(other)"
        }
    }
    private func footer(_ result: Challenge.Result?, other: Challenge.Side) -> String {
        guard result == nil else { return "Le temps officiel est mesuré par le serveur." }
        return other.startedMs == nil
            ? "Votre chrono reste caché jusqu’à ce que \(other.name) joue. Il a 48 h pour relever le défi."
            : "\(other.name) est en train de jouer. Le résultat apparaîtra sur l’accueil."
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).scaledFont(18, .bold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).scaledFont(12).foregroundStyle(Palette.tertiary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.fill1))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
