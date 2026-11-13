import SwiftUI
import CNSNNCore

// Duel en direct: looking for an opponent (or waiting for a friend with a link), the 3-2-1, the 5 words
// with the other player's progress on top, then the result. Same lilac as the friend challenges.

struct LiveDuelView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session: LiveDuelSession
    @State private var confirmQuit = false
    @State private var shakes: CGFloat = 0
    @State private var showPassed = false

    init(start: LiveDuelSession.Start) { _session = State(initialValue: LiveDuelSession(start: start)) }

    var body: some View {
        ZStack {
            AmbientBackground(dimmed: session.phase == .live)
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                VStack(spacing: 0) {
                    topBar
                    content
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 6).readableWidth()
            }
        }
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .task {
            session.myUID = state.uid
            if session.phase == .connecting { await session.begin(state: state) }
        }
        .onDisappear { session.leave(state: state) }
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
        .confirmationDialog("Quitter le duel ?", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("Abandonner", role: .destructive) { session.leave(state: state); dismiss() }
            Button("Continuer à jouer", role: .cancel) {}
        } message: { Text("Quitter maintenant fait perdre le duel.") }
    }

    private var duelState: LiveDuel.State? { session.state(uid: state.uid) }
    private var opponent: LiveDuel.Side? {
        guard let uid = state.uid, let duel = session.duel, !duel.isOpen else { return nil }
        return duel.theirs(uid)
    }

    private var topBar: some View {
        HStack {
            CircleIconButton(symbol: "xmark", label: "Quitter") {
                switch duelState {
                case .countdown?, .playing?: confirmQuit = true
                default: session.leave(state: state); dismiss()
                }
            }
            Spacer()
            if duelState == .playing, let game = session.game {
                let ms = game.scoreMs(elapsed: session.elapsedMs)
                Text(ChallengeFormat.time(ms)).scaledFont(14, .bold).monospacedDigit()
                    .padding(.horizontal, 13).frame(minHeight: 36).glassCapsule()
                    .accessibilityLabel("Chrono : " + ChallengeFormat.time(ms))
            }
        }
        .overlay {
            VStack(spacing: 1) {
                Text("Duel en direct").scaledFont(16, .semibold)
                if let opponent { Text("contre " + opponent.name).scaledFont(12).foregroundStyle(Palette.tertiary) }
            }.lineLimit(1).accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
        }
        .frame(minHeight: 48)
    }

    @ViewBuilder private var content: some View {
        switch session.phase {
        case .connecting:
            centered { ProgressView().tint(Palette.secondary); line("Connexion…") }
        case .searching(let since):
            let left = max(0, LiveDuelRules.searchMs - Int(Date().timeIntervalSince(since) * 1000))
            centered {
                DuelGlyph(size: 72)
                Text("Recherche d’un adversaire…").scaledFont(20, .bold).padding(.top, 18)
                Text(ChallengeFormat.time(left)).scaledFont(15, .semibold).monospacedDigit().foregroundStyle(Palette.duelSoft).padding(.top, 6)
                line("Le premier joueur qui cherche aussi un duel sera votre adversaire.")
            }
        case .nobody:
            centered {
                DuelGlyph(size: 72)
                Text("Personne ne cherche en ce moment").scaledFont(20, .bold).multilineTextAlignment(.center).padding(.top, 18)
                line("Réessayez dans un instant, ou invitez un ami : il vous rejoint avec le lien.")
                Button("Chercher encore") { Haptics.selection(); session.searchAgain(state: state) }
                    .buttonStyle(DuelButtonStyle(height: 50)).padding(.top, 22)
                Button("Inviter un ami par lien") { Haptics.selection(); restart(.link) }
                    .buttonStyle(GlassPillStyle(height: 50)).padding(.top, 10).padding(.horizontal, 30)
            }
        case .waiting:
            waiting
        case .live:
            live
        case .failed(let text):
            centered {
                Text(text).scaledFont(16).multilineTextAlignment(.center).foregroundStyle(Palette.secondary).padding(.horizontal, 20)
                Button("Réessayer") { restart(session.start) }.buttonStyle(GlassPillStyle(height: 50)).padding(.top, 20).padding(.horizontal, 40)
            }
        }
    }

    private func centered<Content: View>(@ViewBuilder _ inner: () -> Content) -> some View {
        VStack(spacing: 0) {
            Spacer()
            inner()
            Spacer()
        }.frame(maxWidth: .infinity)
    }
    private func line(_ text: String) -> some View {
        Text(text).scaledFont(14).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 24).padding(.top, 10)
    }
    private func restart(_ start: LiveDuelSession.Start) {
        session.leave(state: state)
        session = LiveDuelSession(start: start)
        session.myUID = state.uid
        Task { await session.begin(state: state) }
    }

    // MARK: Waiting for a friend

    private var waiting: some View {
        centered {
            DuelGlyph(size: 64)
            Text("Envoyez ce code à un ami").scaledFont(20, .bold).padding(.top, 16)
            Text(session.duel?.code ?? "······").font(.system(size: 44, weight: .heavy, design: .rounded)).tracking(6)
                .foregroundStyle(Palette.duelText).padding(.top, 10).textSelection(.enabled)
                .accessibilityLabel("Code : " + (session.duel?.code.map { $0.map(String.init).joined(separator: " ") } ?? ""))
            if let code = session.duel?.code {
                ShareLink(item: LiveDuelInvite.shareText(code: code)) { Label("Envoyer le lien", systemImage: "square.and.arrow.up") }
                    .buttonStyle(DuelButtonStyle(height: 50)).padding(.top, 18)
                    .accessibilityIdentifier("shareLiveDuel")
            }
            HStack(spacing: 8) {
                ProgressView().tint(Palette.duelSoft)
                Text("En attente de votre ami…").scaledFont(14, .semibold).foregroundStyle(Palette.duelSoft)
            }.padding(.top, 24)
            line("Il a 15 minutes pour ouvrir le lien ou taper le code dans « Défier un ami ». Gardez cet écran ouvert : le duel démarre dès qu’il arrive.")
        }
    }

    // MARK: The duel

    @ViewBuilder private var live: some View {
        if let duel = session.duel, let uid = state.uid, let game = session.game {
            switch duel.state(for: uid, now: session.nowMs) {
            case .countdown:
                let left = max(1, Int(ceil(Double((duel.startMs ?? 0) - session.nowMs) / 1000)))
                centered {
                    Text("Duel contre").scaledFont(15).foregroundStyle(Palette.secondary)
                    Text(duel.theirs(uid).name).scaledFont(26, .bold).padding(.top, 2)
                    Text("\(min(left, 5))").font(.system(size: 120, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(Palette.duelText).padding(.top, 20)
                        .contentTransition(.numericText()).animation(reduceMotion ? nil : .snappy, value: left)
                    line("Mêmes 5 mots, au même moment. Chaque mot passé ajoute 20 s.")
                }
            case .playing:
                tracks(duel, uid: uid, game: game)
                if game.finished {
                    // The finish is on its way to the server, which stamps the official time.
                    centered { ProgressView().tint(Palette.secondary); line("Envoi de votre temps…") }
                } else {
                    board(game)
                }
            case .finished:
                tracks(duel, uid: uid, game: game)
                centered {
                    Text("Votre temps").scaledFont(14).foregroundStyle(Palette.tertiary)
                    Text(ChallengeFormat.time(duel.scoreMs(duel.mine(uid)) ?? game.scoreMs(elapsed: session.elapsedMs)))
                        .font(.system(size: 64, weight: .heavy)).monospacedDigit()
                    let left = duel.leftToBeatMs(for: uid, now: session.nowMs) ?? 0
                    line("\(duel.theirs(uid).name) doit finir en moins de \(ChallengeFormat.time(left)) pour vous battre.")
                }
            case .waiting:
                centered { ProgressView().tint(Palette.secondary) }
            case .over(let result):
                tracks(duel, uid: uid, game: game)
                Spacer(minLength: 8)
                resultPanel(duel, uid: uid, result: result, game: game)
            }
        } else {
            centered { ProgressView().tint(Palette.secondary) }
        }
    }

    /// Both players' progress, one capsule per word: the other one's moves come in live.
    private func tracks(_ duel: LiveDuel, uid: String, game: ChallengeGame) -> some View {
        VStack(spacing: 8) {
            track(name: "Vous", uid: uid, done: max(game.index, duel.mine(uid).done), finished: game.finished, quit: false)
            let other = duel.theirs(uid)
            track(name: other.name, uid: other.uid, done: other.done, finished: other.finished, quit: other.quit)
        }
        .padding(.horizontal, 14).padding(.vertical, 10).modifier(DuelSurface(radius: 20)).padding(.top, 8)
    }
    private func track(name: String, uid: String, done: Int, finished: Bool, quit: Bool) -> some View {
        HStack(spacing: 10) {
            AvatarView(name: name, colorIndex: avatarIndex(uid), size: 24)
            Text(name).scaledFont(13, .semibold).lineLimit(1).frame(width: 86, alignment: .leading)
            HStack(spacing: 4) {
                ForEach(0..<ChallengeRules.words, id: \.self) { index in
                    Capsule().fill(index < done ? Palette.duel : Palette.fill2).frame(height: 6)
                }
            }
            Text(quit ? "parti" : finished ? "fini" : "\(done)/\(ChallengeRules.words)")
                .scaledFont(12, .semibold).monospacedDigit().foregroundStyle(Palette.tertiary).frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(quit ? "\(name) a quitté" : "\(name) : \(done) mots sur \(ChallengeRules.words)")
        .animation(reduceMotion ? nil : .snappy, value: done)
    }

    private func board(_ game: ChallengeGame) -> some View {
        WordsBoard(game: game, answer: session.answer, answerWrong: session.answerWrong, cursor: session.cursor,
                   passed: session.passed, showPassed: showPassed, shakes: shakes,
                   press: session.press, delete: session.delete, clear: session.clear, moveCursor: session.moveCursor,
                   placeCursor: session.placeCursor, skip: { session.skip(state: state) }, submit: { session.submit(state: state) })
    }

    // MARK: Result

    private func resultPanel(_ duel: LiveDuel, uid: String, result: LiveDuel.Result, game: ChallengeGame) -> some View {
        let me = duel.mine(uid), other = duel.theirs(uid)
        return VStack(spacing: 0) {
            Text(title(result, other: other)).font(Typo.serifItalic(26))
                .foregroundStyle(result == .won ? Palette.mint : result == .lost ? Palette.red : Palette.duelSoft)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                tile(duel.scoreMs(me).map(ChallengeFormat.time) ?? (me.quit ? "abandon" : "—"), "vous")
                tile(duel.scoreMs(other).map(ChallengeFormat.time) ?? (other.quit ? "abandon" : "—"), other.name)
            }.padding(.top, 18)
            if !game.missed.isEmpty {
                Text((game.missed.count > 1 ? "Les réponses manquées : " : "La réponse manquée : ") + game.missed.map { "« \($0) »" }.joined(separator: ", ") + ".")
                    .scaledFont(13).foregroundStyle(Palette.tertiary).multilineTextAlignment(.center).padding(.top, 10)
            }
            Text("Le temps officiel est mesuré par le serveur. Chaque mot passé compte 20 s.")
                .scaledFont(12).foregroundStyle(Palette.tertiary).multilineTextAlignment(.center).padding(.top, 12)
            HStack(spacing: 10) {
                Button("Rejouer") { Haptics.selection(); restart(session.start == .random ? .random : .link) }
                    .buttonStyle(GlassPillStyle(height: 54)).accessibilityIdentifier("liveDuelAgain")
                Button("Terminer") { dismiss() }.buttonStyle(PrimaryPillStyle(height: 54))
            }.padding(.top, 20)
        }
        .padding(.horizontal, 22).padding(.vertical, 26)
        .modifier(DuelSurface(radius: 40))
        .padding(.bottom, 12)
        .onAppear {
            if result == .won { Haptics.success() } else if result == .lost { Haptics.failure() }
            session.resend(state: state)
        }
    }
    private func title(_ result: LiveDuel.Result, other: LiveDuel.Side) -> String {
        switch result {
        case .won: other.quit ? "\(other.name) a abandonné : victoire !" : "Victoire contre \(other.name) !"
        case .lost: "\(other.name) a été plus rapide…"
        case .draw: "Égalité !"
        }
    }
    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).scaledFont(22, .bold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).scaledFont(12).foregroundStyle(Palette.tertiary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.fill1))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// The 5 words of a duel or a tournament match: the clue, the answer line, "Passer" and the keyboard.
struct WordsBoard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let game: ChallengeGame
    let answer: String
    let answerWrong: Bool
    let cursor: Int?
    let passed: String?
    let showPassed: Bool
    let shakes: CGFloat
    let press: (String) -> Void
    let delete: () -> Void
    let clear: () -> Void
    let moveCursor: (Int) -> Void
    let placeCursor: (Int) -> Void
    let skip: () -> Void
    let submit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let card = game.card { clue(card, number: game.index + 1) }
            Spacer(minLength: 8).overlay {
                ZStack {
                    if showPassed, let passed {
                        Text("C’était : " + passed.uppercased())
                            .scaledFont(14, .semibold).foregroundStyle(Palette.secondary).lineLimit(1).minimumScaleFactor(0.6).fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14).frame(minHeight: 32).glassCapsule()
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: showPassed)
                .accessibilityHidden(true)
            }
            answerLine
            Button { Haptics.selection(); skip() } label: {
                Text("Passer · +20 s").scaledFont(13, .medium).foregroundStyle(Palette.secondary)
                    .padding(.horizontal, 16).frame(minHeight: 36).glassCapsule().hitTarget()
            }
            .buttonStyle(PressStyle()).accessibilityLabel("Passer ce mot, 20 secondes de pénalité").padding(.vertical, 10)
            LetterKeyboard(press: press, delete: delete, clear: clear, moveCursor: moveCursor, submit: submit)
        }
    }

    private func clue(_ card: Card, number: Int) -> some View {
        VStack(spacing: 0) {
            Text("Mot \(number) sur \(ChallengeRules.words)").scaledFont(12).foregroundStyle(Palette.tertiary)
            let consonants = card.wordNoVowels
            Text(consonants)
                .font(Typo.serif(consonants.count > 5 ? 56 : 72)).tracking(3)
                .lineLimit(1).minimumScaleFactor(0.35).padding(.top, 4)
                .accessibilityLabel("Consonnes : " + WordEngine.spoken(consonants))
                .id(card.id)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .offset(y: 12).combined(with: .opacity), removal: .opacity))
            Text("\(card.category.rawValue) · \(card.difficulty.rawValue)").scaledFont(12).foregroundStyle(Palette.tertiary).padding(.top, 2)
            Text("« \(card.hint) »").font(Typo.serifItalic(20)).multilineTextAlignment(.center).lineSpacing(2)
                .lineLimit(3).minimumScaleFactor(0.7).padding(.horizontal, 10).padding(.top, 10)
                .id("hint-" + card.id)
        }
        .padding(.top, 12)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: card.id)
    }

    private var answerLine: some View {
        HStack(spacing: 2) {
            if answer.isEmpty {
                Text("votre réponse").font(Typo.serifItalic(22)).foregroundStyle(Palette.tertiary)
            }
            if !answer.isEmpty { AnswerLetters(answer: answer, wrong: answerWrong, cursor: cursor, place: placeCursor) }
            if TypedAnswer(text: answer, cursor: cursor).inside == nil { Caret() }
        }
        .lineLimit(1).minimumScaleFactor(0.4)
        .frame(maxWidth: .infinity, minHeight: 52)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.tertiary).frame(height: 1) }
        .padding(.horizontal, 24)
        .modifier(Shake(animatableData: shakes))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Votre réponse")
        .accessibilityValue(answer.isEmpty ? "vide" : answer)
    }
}
