import SwiftUI
import CNSNNCore

/// Sprint, Survie and Double sens, in full screen. Same board, keyboard and glass as the other games;
/// each mode adds its own header (clock, hearts or rounds) and its results.
struct ModeGameView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session: ModeSession
    @State private var confirmQuit = false
    @State private var shakes: CGFloat = 0
    @State private var showGain = false
    @State private var showPassed = false
    let mode: PlayMode

    init(mode: PlayMode) {
        self.mode = mode
        _session = State(initialValue: ModeSession(mode: mode))
    }

    var body: some View {
        ZStack {
            AmbientBackground(dimmed: !session.over)
            VStack(spacing: 0) {
                topBar
                if session.over { Spacer() } else { content }
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 6).readableWidth()
            if session.over {
                Palette.dim.ignoresSafeArea().transition(.opacity)
                VStack {
                    Spacer()
                    ModeResultView(session: session, replay: replay, close: { dismiss() }).padding(.horizontal, 8)
                }.readableWidth().transition(.move(edge: .bottom))
            }
        }
        .animation(reduceMotion ? nil : CNSNNTheme.ease, value: session.over)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .task {
            if session.sprint == nil && session.survival == nil && session.duo == nil { session.begin(state: state) }
            guard mode == .sprint else { return }
            // The Sprint clock: ends the game the moment the time is up.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                session.tick(state: state)
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { session.tick(state: state) } }
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
        .onChange(of: session.successTick) { _, _ in
            guard mode == .sprint else { return }
            showGain = true
            Task { try? await Task.sleep(for: .seconds(0.9)); showGain = false }
        }
        .confirmationDialog(quitTitle, isPresented: $confirmQuit, titleVisibility: .visible) {
            if mode != .sprint {
                Button("Reprendre plus tard") { dismiss() }
            }
            Button(mode == .sprint ? "Arrêter le sprint" : "Abandonner", role: .destructive) { session.quit(state: state) }
            Button("Continuer à jouer", role: .cancel) {}
        } message: { Text(quitMessage) }
    }

    private var quitTitle: String { mode == .sprint ? "Arrêter le sprint ?" : "Quitter la partie ?" }
    private var quitMessage: String {
        switch mode {
        case .sprint: "La partie est comptée avec votre score actuel."
        case .survival: "Vous pouvez la reprendre plus tard depuis l’accueil, ou l’abandonner : elle sera comptée telle quelle."
        case .duo: "Vous pouvez la reprendre plus tard (le chrono continue), ou l’abandonner : les manches restantes compteront comme perdues."
        }
    }

    private func replay() {
        Haptics.selection()
        session.begin(state: state)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            CircleIconButton(symbol: "xmark", label: "Quitter") {
                if session.over || session.finished { dismiss() } else { confirmQuit = true }
            }
            Spacer()
            trailing
        }
        .overlay {
            VStack(spacing: 1) {
                Text(mode.title).scaledFont(16, .semibold)
                Text(subtitle).scaledFont(12).foregroundStyle(Palette.tertiary)
            }.lineLimit(1).accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
        }
        .frame(minHeight: 48)
    }

    private var subtitle: String {
        switch mode {
        case .sprint: return "90 secondes"
        case .survival: return session.resumed ? "Partie reprise" : "3 vies"
        case .duo:
            guard let duo = session.duo else { return "" }
            return "Manche \(min(duo.round + 1, duo.duos.count)) sur \(duo.duos.count)"
        }
    }

    @ViewBuilder private var trailing: some View {
        switch mode {
        case .sprint:
            pill(Format.number(session.sprint?.found ?? 0), label: "Mots")
        case .survival:
            Hearts(lives: session.survival?.lives ?? 3, lost: session.lifeLostTick, gained: session.lifeGainedTick)
        case .duo:
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                pill(Format.clock(session.duo?.playMs(elapsed: session.elapsedMs) ?? 0), label: "Chrono")
            }
        }
    }

    private func pill(_ value: String, label: String) -> some View {
        Text(value).scaledFont(14, .bold).monospacedDigit().foregroundStyle(Palette.foreground)
            .contentTransition(.numericText())
            .padding(.horizontal, 13).frame(minHeight: 36).glassCapsule()
            .accessibilityLabel("\(label) : \(value)")
    }

    // MARK: Board

    @ViewBuilder private var content: some View {
        switch mode {
        case .sprint: if let game = session.sprint { sprintBoard(game) }
        case .survival: if let game = session.survival { survivalBoard(game) }
        case .duo: if let game = session.duo { duoBoard(game) }
        }
    }

    @ViewBuilder private func sprintBoard(_ game: SprintGame) -> some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            SprintClock(remainingMs: game.remainingMs(elapsed: session.elapsedMs))
        }.padding(.top, 6)
        HStack(spacing: 8) {
            stat("\(game.found)", game.found > 1 ? "mots" : "mot")
            stat("×\(max(1, game.streak))", "combo", highlight: game.streak > 1)
            stat(showGain ? (session.gain ?? "") : "\(game.accuracy) %", showGain ? "trouvé" : "précision", highlight: showGain)
        }.padding(.top, 12)
        if let card = game.card { clue(card) }
        // Over the free space, so the board never moves.
        Spacer(minLength: 8).overlay { passedLine }
        answerLine
        actions(skip: "Passer · −5 s", skipLabel: "Passer ce mot, 5 secondes de pénalité")
        LetterKeyboard(press: session.press, delete: session.delete, clear: session.clear, moveCursor: session.moveCursor, submit: { session.submit(state: state) })
    }

    @ViewBuilder private func survivalBoard(_ game: SurvivalGame) -> some View {
        HStack(spacing: 8) {
            stat("\(game.found)", game.found > 1 ? "mots trouvés" : "mot trouvé")
            stat("\(game.level)", "niveau")
            stat(game.card?.difficulty.rawValue ?? "—", "difficulté")
        }.padding(.top, 10)
        Text(SurvivalGame.bonusEvery - game.found % SurvivalGame.bonusEvery == 1 ? "Encore 1 mot pour regagner une vie" : "Une vie regagnée tous les \(SurvivalGame.bonusEvery) mots")
            .scaledFont(12).foregroundStyle(Palette.tertiary).padding(.top, 8)
        if let card = game.card { clue(card) }
        // Over the free space, so the board never moves.
        Spacer(minLength: 8).overlay { passedLine }
        answerLine
        actions(skip: "Passer · −1 vie", skipLabel: "Passer ce mot, une vie en moins")
        LetterKeyboard(press: session.press, delete: session.delete, clear: session.clear, moveCursor: session.moveCursor, submit: { session.submit(state: state) })
    }

    @ViewBuilder private func duoBoard(_ game: DuoGame) -> some View {
        if let duo = game.duo {
            let consonants = duo.consonants
            Text(consonants)
                .font(Typo.serif(consonants.count > 4 ? 64 : 84)).tracking(4)
                .lineLimit(1).minimumScaleFactor(0.4).padding(.top, 18)
                .accessibilityLabel("Consonnes : " + WordEngine.spoken(consonants))
            Text("Deux mots, les mêmes consonnes").scaledFont(12).foregroundStyle(Palette.tertiary).padding(.top, 2)
            VStack(spacing: 10) {
                DuoClueRow(number: 1, word: duo.first, found: game.found[game.round][0], revealed: game.roundComplete)
                DuoClueRow(number: 2, word: duo.second, found: game.found[game.round][1], revealed: game.roundComplete)
            }.padding(.top, 16)
            Spacer(minLength: 8)
            if game.roundComplete {
                Button(game.finished ? "Voir le résultat" : "Manche suivante") { Haptics.selection(); session.nextRound(state: state) }
                    .buttonStyle(PrimaryPillStyle(height: 54)).padding(.bottom, 12)
            } else {
                answerLine
                actions(skip: "Passer la manche", skipLabel: "Passer la manche et voir les mots")
                LetterKeyboard(press: session.press, delete: session.delete, clear: session.clear, moveCursor: session.moveCursor, submit: { session.submit(state: state) })
            }
        }
    }

    /// "C'était : TOURNESOL" for two seconds after a pass, so the answer is never lost.
    /// Built only while shown: Liquid Glass ignores a zero opacity, so a hidden capsule left an empty bubble.
    private var passedLine: some View {
        ZStack {
            if showPassed, let passed = session.passed {
                Text("C’était : " + passed.uppercased())
                    .scaledFont(14, .semibold).foregroundStyle(Palette.secondary).lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.horizontal, 14).frame(minHeight: 32).glassCapsule()
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: showPassed)
        .accessibilityHidden(true)
    }

    private func clue(_ card: Card) -> some View {
        VStack(spacing: 0) {
            let consonants = card.wordNoVowels
            Text(consonants)
                .font(Typo.serif(consonants.count > 5 ? 60 : 80)).tracking(3)
                .lineLimit(1).minimumScaleFactor(0.35)
                .accessibilityLabel("Consonnes : " + WordEngine.spoken(consonants))
                .id(card.id)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .offset(y: 12).combined(with: .opacity), removal: .opacity))
            Text("\(card.category.rawValue) · \(card.difficulty.rawValue)").scaledFont(12).foregroundStyle(Palette.tertiary).padding(.top, 4)
            Text("« \(card.hint) »").font(Typo.serifItalic(22)).multilineTextAlignment(.center).lineSpacing(2)
                .lineLimit(3).minimumScaleFactor(0.7)
                .padding(.horizontal, 10).padding(.top, 14)
                .id("hint-" + card.id)
        }
        .padding(.top, 16)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: card.id)
    }

    private func stat(_ value: String, _ label: String, highlight: Bool = false) -> some View {
        VStack(spacing: 1) {
            Text(value).scaledFont(18, .bold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(highlight ? Palette.mint : Palette.foreground)
                .contentTransition(.numericText())
            Text(label).scaledFont(11).foregroundStyle(Palette.tertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.fill1))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .animation(reduceMotion ? nil : CNSNNTheme.spring, value: value)
    }

    private var answerLine: some View {
        HStack(spacing: 2) {
            if session.answer.isEmpty {
                Text("votre réponse").font(Typo.serifItalic(22)).foregroundStyle(Palette.tertiary)
            }
            if !session.answer.isEmpty { AnswerLetters(answer: session.answer, wrong: session.answerWrong, cursor: session.cursor, place: session.placeCursor) }
            if TypedAnswer(text: session.answer, cursor: session.cursor).inside == nil { Caret() }
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

    private func actions(skip: String, skipLabel: String) -> some View {
        Button { Haptics.selection(); session.skip(state: state) } label: {
            Text(skip).scaledFont(13, .medium).foregroundStyle(Palette.secondary)
                .padding(.horizontal, 16).frame(minHeight: 36).glassCapsule().hitTarget()
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(skipLabel)
        .padding(.vertical, 10)
    }
}

// MARK: - Pieces

/// The Sprint countdown: a thin bar and the seconds left. The last ten seconds turn red and beat
/// gently, with a light tap for each of the last five.
private struct SprintClock: View {
    var remainingMs: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var seconds: Int { (remainingMs + 999) / 1000 }
    private var low: Bool { remainingMs <= 10_000 }
    var body: some View {
        HStack(spacing: 12) {
            Text(Format.clock(seconds * 1000)).scaledFont(17, .bold).monospacedDigit()
                .foregroundStyle(low ? Palette.red : Palette.foreground)
                .scaleEffect(low && !reduceMotion && seconds % 2 == 0 ? 1.06 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: seconds)
                .frame(minWidth: 52, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.fill1)
                    Capsule().fill(low ? Palette.red : Palette.foreground)
                        .frame(width: geo.size.width * CGFloat(remainingMs) / CGFloat(SprintGame.durationMs))
                        .animation(reduceMotion ? nil : .linear(duration: 0.2), value: remainingMs)
                }
            }.frame(height: 6)
        }
        .onChange(of: seconds) { _, value in if (1...5).contains(value) { Haptics.key() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Temps restant")
        .accessibilityValue("\(seconds) secondes")
    }
}

private struct Hearts: View {
    var lives: Int
    var lost: Int
    var gained: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<SurvivalGame.maxLives, id: \.self) { index in
                Image(systemName: index < lives ? "heart.fill" : "heart")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(index < lives ? Palette.red : Palette.tertiary)
                    .symbolEffect(.bounce.down, value: reduceMotion ? 0 : lost)
                    .symbolEffect(.bounce.up, value: reduceMotion || index != lives - 1 ? 0 : gained)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .padding(.horizontal, 12).frame(minHeight: 36).glassCapsule()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(lives) vie\(lives > 1 ? "s" : "") sur \(SurvivalGame.maxLives)")
    }
}

/// One clue of a Double sens round, and its word once found (gold vowels) or given up (grey vowels).
private struct DuoClueRow: View {
    var number: Int
    var word: DuoWord
    var found: Bool
    var revealed: Bool
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(number)").scaledFont(13, .bold).foregroundStyle(found ? Palette.ink : Palette.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(found ? Palette.mint : Palette.fill2))
            VStack(alignment: .leading, spacing: 6) {
                Text(word.hint).font(Typo.serifItalic(19)).foregroundStyle(Palette.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if found || revealed {
                    RevealedWord(word: word.word, correct: found)
                } else {
                    Text("à trouver").scaledFont(12).foregroundStyle(Palette.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(found ? Palette.fill2 : Palette.fill1))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(found ? Palette.mint.opacity(0.5) : Palette.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Indice \(number) : \(word.hint)" + (found ? ". Trouvé : \(word.word)" : revealed ? ". Réponse : \(word.word)" : ""))
    }
}

/// The word, its vowels sliding in once it appears.
private struct RevealedWord: View {
    var word: String
    var correct: Bool
    @State private var revealed = false
    var body: some View {
        VowelReveal(word: word.uppercased(), correct: correct, revealed: revealed, maxSize: 26, width: 230)
            .frame(height: 32, alignment: .leading)
            .onAppear { revealed = true }
    }
}

// MARK: - Results

private struct ModeResultView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var session: ModeSession
    var replay: () -> Void
    var close: () -> Void
    @State private var celebrate = false

    var body: some View {
        VStack(spacing: 0) {
            Text(kicker).font(Typo.serifItalic(24)).foregroundStyle(Palette.secondary)
            Text(Format.number(mainValue)).font(.system(size: 64, weight: .heavy)).tracking(-1.5).monospacedDigit()
                .foregroundStyle(Palette.foreground).padding(.top, 6)
            Text(mainLabel).scaledFont(13).foregroundStyle(Palette.tertiary)
            HStack(spacing: 10) {
                ForEach(tiles, id: \.1) { value, label in tile(value, label) }
            }.padding(.top, 18)
            recordLine.padding(.top, 14)
            if let missed { Text(missed).scaledFont(13).foregroundStyle(Palette.tertiary).multilineTextAlignment(.center).padding(.top, 8) }
            HStack(spacing: 10) {
                Button("Accueil", action: close).buttonStyle(GlassPillStyle(height: 54))
                Button("Rejouer", action: replay).buttonStyle(PrimaryPillStyle(height: 54))
            }.padding(.top, 20)
            Text("Record personnel : il ne compte pas dans les classements du mot du jour.")
                .scaledFont(11).foregroundStyle(Palette.tertiary).multilineTextAlignment(.center).padding(.top, 12)
        }
        .padding(.horizontal, 22).padding(.vertical, 26)
        .background {
            let shape = RoundedRectangle(cornerRadius: 48, style: .continuous)
            shape.fill(.ultraThinMaterial).overlay(shape.fill(LinearGradient(colors: [Palette.sheetTop, Palette.sheetBottom], startPoint: .top, endPoint: .bottom)))
                .overlay(shape.strokeBorder(LinearGradient(colors: [Palette.glassHighlight, Palette.glassBorder], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .shadow(color: Palette.glassShadow, radius: 30, y: -20)
        }
        .onAppear {
            if session.improved(mainKey) {
                Haptics.success()
                AccessibilityNotification.Announcement("Nouveau record personnel").post()
                if !reduceMotion { withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.25)) { celebrate = true } }
            }
        }
    }

    private var mainKey: String {
        switch session.mode { case .sprint: ModeStat.words; case .survival: ModeStat.level; case .duo: ModeStat.duo }
    }
    private var records: ModeRecords { state.progress.records(session.mode) }

    private var kicker: String {
        switch session.mode {
        case .sprint: return (session.sprint?.remainingMs(elapsed: session.elapsedMs) ?? 0) == 0 ? "Temps écoulé !" : "Sprint arrêté"
        case .survival: return (session.survival?.lives ?? 0) == 0 ? "Plus de vies…" : "Partie terminée"
        case .duo: return session.duo?.perfect == true ? "Parfait, 10 sur 10 !" : "Partie terminée"
        }
    }
    private var mainValue: Int {
        switch session.mode {
        case .sprint: return session.sprint?.found ?? 0
        case .survival: return session.survival?.level ?? 1
        case .duo: return session.duo?.solved ?? 0
        }
    }
    private var mainLabel: String {
        switch session.mode {
        case .sprint: return mainValue > 1 ? "mots trouvés en 90 s" : "mot trouvé en 90 s"
        case .survival: return "niveau atteint"
        case .duo: return mainValue > 1 ? "paires trouvées" : "paire trouvée"
        }
    }

    private var tiles: [(String, String)] {
        switch session.mode {
        case .sprint:
            guard let game = session.sprint else { return [] }
            return [("\(game.bestCombo)", "meilleur combo"), ("\(game.accuracy) %", "précision"), ("\(game.skips)", game.skips > 1 ? "passés" : "passé")]
        case .survival:
            guard let game = session.survival else { return [] }
            return [("\(game.found)", game.found > 1 ? "mots trouvés" : "mot trouvé"), ("\(game.mistakes)", game.mistakes > 1 ? "erreurs" : "erreur"), (Format.number(records.best(ModeStat.words)), "meilleur parcours")]
        case .duo:
            guard let game = session.duo else { return [] }
            return [(Format.clock(game.playMs(elapsed: session.elapsedMs)), "temps"), ("\(game.wordsFound)/\(game.duos.count * 2)", "réponses"), ("\(game.errors)", game.errors > 1 ? "erreurs" : "erreur")]
        }
    }

    /// The answers not found: the words passed, then the one the time or the last life ended on.
    private var missed: String? {
        var words: [String]
        switch session.mode {
        case .sprint:
            guard let game = session.sprint else { return nil }
            words = game.missed ?? []
            if let card = game.card, game.remainingMs(elapsed: session.elapsedMs) == 0, words.last != card.wordFull { words.append(card.wordFull) }
        case .survival:
            guard let game = session.survival else { return nil }
            words = game.missed ?? []
            if game.lives == 0, let card = game.card, words.last != card.wordFull { words.append(card.wordFull) }
        case .duo: return nil
        }
        guard !words.isEmpty else { return nil }
        return (words.count > 1 ? "Les réponses manquées : " : "La réponse manquée : ") + words.map { "« \($0) »" }.joined(separator: ", ") + "."
    }

    @ViewBuilder private var recordLine: some View {
        if session.improved(mainKey) {
            Label("Nouveau record personnel", systemImage: "trophy.fill")
                .scaledFont(15, .bold).foregroundStyle(Palette.mint)
                .scaleEffect(celebrate || reduceMotion ? 1 : 0.85).opacity(celebrate || reduceMotion ? 1 : 0.6)
                .symbolEffect(.bounce, value: celebrate)
        } else if session.beaten.contains(mainKey) {
            Label("Premier record établi", systemImage: "flag.checkered").scaledFont(14, .semibold).foregroundStyle(Palette.secondary)
        } else {
            Text("Record : " + ModeRecordText.main(session.mode, records))
                .scaledFont(14, .semibold).foregroundStyle(Palette.secondary)
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).scaledFont(20, .bold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).scaledFont(12).foregroundStyle(Palette.tertiary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.fill1))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// The main personal record of a mode, as words (no points anywhere).
enum ModeRecordText {
    static func main(_ mode: PlayMode, _ records: ModeRecords) -> String {
        switch mode {
        case .sprint:
            let words = records.best(ModeStat.words)
            return "\(words) " + (words > 1 ? "mots" : "mot")
        case .survival: return "niveau \(max(1, records.best(ModeStat.level)))"
        case .duo:
            let best = records.best(ModeStat.duo)
            guard best > 0 else { return "aucun" }
            let solved = DuoRecord.solved(best)
            return "\(solved) " + (solved > 1 ? "paires" : "paire") + " en " + Format.clock(DuoRecord.seconds(best) * 1000)
        }
    }
}
